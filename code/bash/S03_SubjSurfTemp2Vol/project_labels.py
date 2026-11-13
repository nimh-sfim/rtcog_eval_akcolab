#!/usr/bin/env python3
"""Project a cortical fsaverage6 CIFTI-2 label map through subject anatomy.

Requires Python >= 3.9, NumPy, FreeSurfer and AFNI. The input reader supports
NIfTI-1/2 single-file containers, CIFTI-2 dense labels, and MGH/MGZ overlays.
Neuromaps, NiBabel and Workbench are not dependencies.
"""
import argparse
import csv
import gzip
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import struct
import subprocess
import sys
import xml.etree.ElementTree as ET

import numpy as np

DTYPES = {2:'u1',4:'i2',8:'i4',16:'f4',64:'f8',256:'i1',512:'u2',768:'u4',1024:'i8',1280:'u8'}
HEMIS = {'CIFTI_STRUCTURE_CORTEX_LEFT':'lh', 'CIFTI_STRUCTURE_CORTEX_RIGHT':'rh'}
NVERT = 40962


def require(condition, message):
    if not condition:
        raise ValueError(message)


def read_nifti(path, data=True):
    """Decode the supported single-file NIfTI subset, including scaling."""
    path = Path(path)
    with (gzip.open(path,'rb') if path.suffix == '.gz' else path.open('rb')) as f:
        first = f.read(4)
        require(len(first) == 4, f'Empty or truncated NIfTI: {path}')
        endian = '<' if struct.unpack('<i',first)[0] in (348,540) else '>'
        size = struct.unpack(endian+'i',first)[0]
        require(size in (348,540), f'Not a NIfTI-1/2 file: {path}')
        header = first + f.read(size-4)
        require(len(header) == size, f'Truncated NIfTI header: {path}')
        unpack = lambda fmt,off: struct.unpack_from(endian+fmt,header,off)
        if size == 348:
            require(header[344:348] == b'n+1\0', 'Paired NIfTI files are not supported.')
            dims = unpack('8h',40)
            datatype, bitpix = unpack('2h',70)
            offset = int(unpack('f',108)[0])
            slope, intercept = unpack('2f',112)
            sform = unpack('h',254)[0]
            rows = np.array(unpack('12f',280)).reshape(3,4)
        else:
            require(header[4:8] == b'n+2\0', 'Paired NIfTI files are not supported.')
            dims = unpack('8q',16)
            datatype, bitpix = unpack('2h',12)
            offset = unpack('q',168)[0]
            slope, intercept = unpack('2d',176)
            sform = unpack('i',348)[0]
            rows = np.array(unpack('12d',400)).reshape(3,4)
        require(1 <= dims[0] <= 7, 'Invalid NIfTI dimensionality.')
        shape = tuple(int(n) for n in dims[1:dims[0]+1])
        require(all(n > 0 for n in shape), 'Invalid NIfTI dimensions.')
        require(datatype in DTYPES, f'Unsupported NIfTI datatype code {datatype}.')
        dtype = np.dtype(endian+DTYPES[datatype])
        require(dtype.itemsize*8 == bitpix, 'NIfTI datatype/bitpix mismatch.')
        require(offset >= size+4, 'Invalid NIfTI data offset.')
        extension_flag = f.read(4)
        extension_bytes = f.read(offset-size-4)
        require(len(extension_bytes) == offset-size-4, 'Truncated NIfTI extensions.')
        extensions = []
        if extension_flag and extension_flag[0]:
            pos = 0
            while pos < len(extension_bytes):
                require(pos+8 <= len(extension_bytes), 'Invalid extension header.')
                esize, ecode = struct.unpack_from(endian+'ii',extension_bytes,pos)
                require(esize >= 8 and esize%16 == 0 and pos+esize <= len(extension_bytes), 'Invalid extension length.')
                extensions.append((ecode,extension_bytes[pos+8:pos+esize].rstrip(b'\0')))
                pos += esize
        affine = np.eye(4)
        affine[:3] = rows
        array = None
        if data:
            count = int(np.prod(shape,dtype=np.int64))
            raw = f.read(count*dtype.itemsize)
            require(len(raw) == count*dtype.itemsize, f'Truncated NIfTI data: {path}')
            array = np.frombuffer(raw,dtype=dtype).reshape(shape,order='F')
            if np.isfinite(slope) and slope != 0:
                require(np.isfinite(intercept), 'Invalid scaling intercept.')
                if slope != 1 or intercept != 0:
                    array = array.astype(np.float64)*slope+intercept
    return dict(path=path,size=size,endian=endian,header=header,shape=shape,
                array=array,sform=sform,affine=affine,extensions=extensions)


def valid_affine(image):
    require(image['sform'] > 0 and np.isfinite(image['affine']).all() and
            abs(np.linalg.det(image['affine'][:3,:3])) > 1e-12,
            f"A valid NIfTI sform is required: {image['path']}")


def as_labels(values, context):
    require(np.isfinite(values).all(), f'{context}: non-finite labels.')
    require(np.array_equal(values,np.rint(values)), f'{context}: noninteger labels.')
    require(np.all((values >= 0)&(values <= 32767)), f'{context}: labels must be 0..32767; 0 is background.')
    return values.astype(np.int32)


def read_dlabel(path, map_index=None):
    image = read_nifti(path)
    require(image['size'] == 540, 'Expected a CIFTI-2 dense-label NIfTI-2 file.')
    xmls = [value for code,value in image['extensions'] if code == 32]
    require(len(xmls) == 1, 'Expected one CIFTI XML extension.')
    root = ET.fromstring(xmls[0])
    require(root.tag == 'CIFTI' and root.get('Version') == '2', 'Expected CIFTI-2.')
    maps = {n.get('AppliesToMatrixDimension'):n for n in root.iter('MatrixIndicesMap')}
    require(set(maps) == {'0','1'}, 'Expected a two-dimensional dense-label CIFTI.')
    label_dims = [k for k,n in maps.items() if n.get('IndicesMapToDataType') == 'CIFTI_INDEX_TYPE_LABELS']
    brain_dims = [k for k,n in maps.items() if n.get('IndicesMapToDataType') == 'CIFTI_INDEX_TYPE_BRAIN_MODELS']
    require(len(label_dims) == len(brain_dims) == 1, 'Input must be dlabel, not dscalar or dtseries.')
    label_dim, brain_dim = int(label_dims[0]), int(brain_dims[0])
    named = maps[str(label_dim)].findall('NamedMap')
    require(len(named) > 0, 'No label maps found.')
    if map_index is None:
        require(len(named) == 1, 'Multiple label maps: specify --map-index (zero-based).')
        map_index = 0
    require(0 <= map_index < len(named), '--map-index is out of range.')
    require(image['shape'][:4] == (1,1,1,1), 'Unexpected CIFTI container dimensions.')
    matrix_shape = list(image['shape'][4:])
    while len(matrix_shape) < 2:
        matrix_shape.append(1)
    require(len(matrix_shape) == 2 or all(n == 1 for n in matrix_shape[2:]), 'Unexpected extra CIFTI dimensions.')
    matrix = image['array'].reshape(matrix_shape[:2],order='F')
    require(matrix.shape[label_dim] == len(named), 'Label-axis length mismatch.')
    vector = as_labels(np.take(matrix,map_index,axis=label_dim),'CIFTI input')
    table = {}
    for node in named[map_index].findall('./LabelTable/Label'):
        table[int(node.get('Key'))] = dict(name=node.text or '',
            rgba=[float(node.get(c,'0')) for c in ('Red','Green','Blue','Alpha')])
    require(set(np.unique(vector)).issubset(table), 'A data label is missing from the label table.')
    require(0 not in table or table[0]['rgba'][3] == 0,
            'Label 0 must be background; the input assigns it an opaque label.')
    table.setdefault(0,dict(name='Background',rgba=[0.,0.,0.,0.]))
    result, covered = {}, np.zeros(vector.size,dtype=bool)
    for model in maps[str(brain_dim)].findall('BrainModel'):
        name = model.get('BrainStructure')
        require(name in HEMIS and model.get('ModelType') == 'CIFTI_MODEL_TYPE_SURFACE',
                'Only bilateral cortical dlabels are supported; subcortex is not silently dropped.')
        hemi = HEMIS[name]
        require(hemi not in result, f'Duplicate brain model for {hemi}.')
        require(int(model.get('SurfaceNumberOfVertices')) == NVERT, f'{hemi}: expected fsaverage6 ({NVERT} vertices).')
        start,count = int(model.get('IndexOffset')),int(model.get('IndexCount'))
        indices = np.array([int(v) for v in model.findtext('VertexIndices','').split()],dtype=np.int64)
        require(0 <= start < vector.size and count > 0 and start+count <= vector.size and
                indices.size == count and np.unique(indices).size == count and
                np.all((indices >= 0)&(indices < NVERT)), f'{hemi}: invalid vertex indices.')
        require(not np.any(covered[start:start+count]), 'Overlapping brain models.')
        covered[start:start+count] = True
        arr = np.zeros(NVERT,dtype=np.int32)
        arr[indices] = vector[start:start+count]
        result[hemi] = arr
    require(set(result) == {'lh','rh'} and covered.all(), 'Expected complete left/right brain-model coverage.')
    require(any(np.any(v) for v in result.values()), 'Input contains only background.')
    return result,table,map_index,named[map_index].findtext('MapName','')


def write_mgh(path, labels):
    # MGH scalar overlay with no anatomical RAS claim for vertex values.
    header = struct.pack('>7ih',1,labels.size,1,1,1,3,0,0).ljust(284,b'\0')
    Path(path).write_bytes(header+labels.astype('>f4').tobytes()+bytes(20))


def read_mgh(path):
    path = Path(path)
    with (gzip.open(path,'rb') if path.suffix == '.mgz' else path.open('rb')) as f:
        header = f.read(284)
        require(len(header) == 284, 'Truncated MGH header.')
        version,x,y,z,frames,code,_ = struct.unpack_from('>7i',header)
        require(version == 1 and code in (0,1,3,4), 'Unsupported MGH overlay.')
        dtype = np.dtype({0:'u1',1:'>i4',3:'>f4',4:'>i2'}[code])
        count = x*y*z*frames
        raw = f.read(count*dtype.itemsize)
        require(len(raw) == count*dtype.itemsize, 'Truncated MGH data.')
        return np.frombuffer(raw,dtype=dtype)


def surface_vertices(path):
    with Path(path).open('rb') as f:
        require(int.from_bytes(f.read(3),'big') == 16777214, f'Expected a FreeSurfer triangle surface: {path}')
        f.readline(); f.readline()
        raw = f.read(8)
        require(len(raw) == 8, f'Truncated surface header: {path}')
        nv,nf = struct.unpack('>2i',raw)
        require(nv > 0 and nf > 0, f'Invalid surface size: {path}')
        return nv


def save_reference(source, dest, index):
    image = read_nifti(source)
    valid_affine(image)
    require(len(image['shape']) >= 3, 'Reference must be a spatial image.')
    array = image['array'].reshape(image['shape'][:3]+(-1,),order='F')
    require(0 <= index < array.shape[-1], '--template-index is out of range.')
    values = array[...,index]
    require(np.isfinite(values).all(), 'Reference has non-finite intensities.')
    header = bytearray(image['header'])
    e,size,shape = image['endian'],image['size'],image['shape'][:3]
    if size == 348:
        struct.pack_into(e+'8h',header,40,3,*shape,1,1,1,1)
        struct.pack_into(e+'2h',header,70,16,32)
        struct.pack_into(e+'f',header,108,352.)
        struct.pack_into(e+'2f',header,112,1.,0.)
        struct.pack_into(e+'h',header,68,0)
        header[328:344] = bytes(16)
    else:
        struct.pack_into(e+'8q',header,16,3,*shape,1,1,1,1)
        struct.pack_into(e+'2h',header,12,16,32)
        struct.pack_into(e+'q',header,168,544)
        struct.pack_into(e+'2d',header,176,1.,0.)
        struct.pack_into(e+'i',header,504,0)
        header[508:524] = bytes(16)
    # Retain spatial transforms; omit stale multi-brick AFNI metadata.
    with gzip.open(dest,'wb') as f:
        f.write(header); f.write(bytes(4)); f.write(values.astype(e+'f4').tobytes(order='F'))
    return image['affine'],shape


def require_file(path):
    path = Path(path).expanduser().resolve()
    require(path.is_file(), f'Missing file: {path}')
    return path


def unique_file(paths, name):
    found = [p.resolve() for p in paths if p.is_file()]
    require(len(found) == 1, f'Expected one {name}; found: {found}. Use explicit --warp/--affine.')
    return found[0]


def input_identity(path, subject):
    ids = re.findall(r'(?:^|[_.])sub-([A-Za-z0-9]+)(?=[_.]|$)',Path(path).name)
    expected = subject[4:] if subject.startswith('sub-') else subject
    require(not ids or all(v == expected for v in ids),
            f'Subject token in {Path(path).name} disagrees with --subject {subject}. '
            'Use --fs-subject if the reconstruction folder has a different name.')


def check_labels(array, allowed, context):
    labels = as_labels(array,context)
    present,counts = np.unique(labels,return_counts=True)
    require(set(present).issubset(allowed), f'{context}: a label absent from the input appeared.')
    require(np.any(labels), f'{context}: output contains only background.')
    return {str(int(k)):int(n) for k,n in zip(present,counts)}


def parser():
    p = argparse.ArgumentParser(description=__doc__,formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument('--dlabel',required=True,help='Subject-specific cortical fsaverage6 .dlabel.nii')
    p.add_argument('--subject',required=True,help='Subject ID for outputs and SSwarper filename lookup')
    p.add_argument('--subjects-dir',default=os.environ.get('SUBJECTS_DIR'),help='FreeSurfer subjects directory (or $SUBJECTS_DIR)')
    p.add_argument('--fs-subject',help='FreeSurfer folder name if different from --subject')
    p.add_argument('--fsaverage6-dir',help='Explicit fsaverage6 directory; otherwise search SUBJECTS_DIR and FREESURFER_HOME/subjects')
    p.add_argument('--sswarper-dir',help='Directory containing anatQQ.<subject>_WARP.nii[.gz] and anatQQ.<subject>.aff12.1D')
    p.add_argument('--warp',help='Explicit SSwarper nonlinear warp, used with --affine')
    p.add_argument('--affine',help='Explicit SSwarper affine, instead of --sswarper-dir')
    p.add_argument('--template',default=str(Path(__file__).resolve().parent/'MNI2009_ref.nii.gz'),help='MNI2009 template; default: bundled reference')
    p.add_argument('--template-index',type=int,default=0,help='Zero-based reference sub-brick; default 0 (SKoff in SSW template)')
    p.add_argument('--map-index',type=int,help='Zero-based label map; required only for multi-map dlabels')
    p.add_argument('--out-dir',required=True,help='NEW output directory; existing directories are never overwritten')
    p.add_argument('--prepare-only',action='store_true',help='Extract labels and reference without FreeSurfer/AFNI')
    return p


def main(argv=None):
    args = parser().parse_args(argv)
    out,manifest = None,None
    try:
        require(re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_.-]*',args.subject), 'Invalid subject ID.')
        dlabel,template = require_file(args.dlabel),require_file(args.template)
        input_identity(dlabel,args.subject)
        labels,table,map_index,map_name = read_dlabel(dlabel,args.map_index)
        allowed = set(np.unique(np.concatenate(list(labels.values()))).tolist()) | {0}
        native,fsavg,warp,affine,native_n = None,None,None,None,{}
        if not args.prepare_only:
            require(bool(args.subjects_dir), 'Supply --subjects-dir or set $SUBJECTS_DIR.')
            subjects = Path(args.subjects_dir).expanduser().resolve()
            fs_subject = args.fs_subject or args.subject
            require(re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_.-]*',fs_subject), 'Invalid reconstruction folder name.')
            require(fs_subject not in ('fsaverage','fsaverage6'), 'Specify the participant reconstruction, not a template.')
            native = subjects/fs_subject
            candidates = [Path(args.fsaverage6_dir).expanduser()] if args.fsaverage6_dir else [subjects/'fsaverage6']
            if not args.fsaverage6_dir and os.environ.get('FREESURFER_HOME'):
                candidates.append(Path(os.environ['FREESURFER_HOME'])/'subjects/fsaverage6')
            fsavg = next((p.resolve() for p in candidates if all((p/'surf'/f'{h}.sphere.reg').is_file() for h in ('lh','rh'))),None)
            require(fsavg is not None, 'Cannot find fsaverage6. Supply --fsaverage6-dir /path/to/fsaverage6. '
                    'Do not substitute fsaverage; recon-all does not need to be rerun.')
            for h in ('lh','rh'):
                require(surface_vertices(require_file(fsavg/'surf'/f'{h}.sphere.reg')) == NVERT, f'{h}: source template is not fsaverage6.')
                native_n[h] = surface_vertices(require_file(native/'surf'/f'{h}.sphere.reg'))
                for name in ('white','pial'):
                    require(surface_vertices(require_file(native/'surf'/f'{h}.{name}')) == native_n[h], f'{h}: native surface vertex counts differ.')
            require_file(native/'mri/orig.mgz'); require_file(native/'mri/ribbon.mgz')
            if args.sswarper_dir:
                require(not args.warp and not args.affine, 'Use --sswarper-dir OR --warp with --affine.')
                directory = Path(args.sswarper_dir).expanduser()
                warp = unique_file([directory/f'anatQQ.{args.subject}_WARP.nii',directory/f'anatQQ.{args.subject}_WARP.nii.gz'],'SSwarper warp')
                affine = require_file(directory/f'anatQQ.{args.subject}.aff12.1D')
            else:
                require(args.warp and args.affine, 'Supply --sswarper-dir, or both --warp and --affine.')
                warp,affine = require_file(args.warp),require_file(args.affine)
            input_identity(warp,args.subject); input_identity(affine,args.subject)
            wh = read_nifti(warp,data=False)
            valid_affine(wh)
            require(len(wh['shape']) >= 4 and np.prod(wh['shape'][3:]) == 3, 'Expected an AFNI warp with three displacement components.')
            mat = np.loadtxt(affine,comments='#')
            require(mat.size == 12 and np.isfinite(mat).all(), 'Expected one finite 3x4 AFNI affine (12 values).')
            require(abs(np.linalg.det(mat.reshape(3,4)[:,:3])) > 1e-12, 'Singular AFNI affine.')
            for command in ('mri_surf2surf','mri_surf2vol','3dNwarpApply'):
                require(shutil.which(command), f'Missing executable: {command}. Configure FreeSurfer and AFNI.')
        output_path = Path(args.out_dir).expanduser().absolute()
        require(not output_path.exists() and not output_path.is_symlink(), f'Output directory already exists: {output_path}')
        output_path.mkdir(parents=True)
        out = output_path.resolve()
        (out/'inputs').mkdir(); (out/'work').mkdir()
        reference = out/'inputs/MNI2009_ref.nii.gz'
        expected_affine,expected_shape = save_reference(template,reference,args.template_index)
        for h in ('lh','rh'):
            write_mgh(out/'inputs'/f'{args.subject}.{h}.fsaverage6.mgh',labels[h])
        with (out/f'{args.subject}_network_labels.tsv').open('w',newline='') as stream:
            writer = csv.writer(stream,delimiter='\t')
            writer.writerow(['id','name','red','green','blue','alpha'])
            for key,value in sorted(table.items()):
                writer.writerow([key,value['name'],*value['rgba']])
        manifest = dict(status='prepared',subject=args.subject,dlabel=str(dlabel),
            dlabel_sha256=hashlib.sha256(dlabel.read_bytes()).hexdigest(),map_index=map_index,
            map_name=map_name,label_ids=sorted(allowed),template=str(template),
            template_index=args.template_index,output_shape=list(expected_shape),
            output_affine=expected_affine.tolist(),source_vertices={h:int(v.size) for h,v in labels.items()},
            commands=[],registration_assumption='FreeSurfer anatomy and SSwarper input anatomy must share world coordinates. This is not verified automatically.')
        manifest_path = out/f'{args.subject}_run_manifest.json'
        def save_manifest():
            manifest_path.write_text(json.dumps(manifest,indent=2)+'\n')
        save_manifest()
        if args.prepare_only:
            print(f'Prepared labels and reference in {out}. No spatial projection performed.')
            return 0
        manifest.update(native_reconstruction=str(native),fsaverage6=str(fsavg),warp=str(warp),affine=str(affine),status='running')
        private_subjects = out/'work/subjects'
        private_subjects.mkdir()
        (private_subjects/'native').symlink_to(native,target_is_directory=True)
        (private_subjects/'fsaverage6').symlink_to(fsavg,target_is_directory=True)
        # Local simple names avoid special characters in AFNI warp expressions.
        warp_local = Path('inputs/nonlinear_warp.nii.gz' if warp.suffix == '.gz' else 'inputs/nonlinear_warp.nii')
        (out/warp_local).symlink_to(warp)
        (out/'inputs/affine.aff12.1D').symlink_to(affine)
        env = os.environ.copy()
        env['SUBJECTS_DIR'] = str(private_subjects)
        log_path = out/f'{args.subject}_pipeline.log'
        def run(command):
            command = [str(v) for v in command]
            print(shlex.join(command),flush=True)
            manifest['commands'].append(command); save_manifest()
            with log_path.open('a') as log:
                log.write('\n$ '+shlex.join(command)+'\n'); log.flush()
                status = subprocess.run(command,cwd=out,env=env,stdout=log,stderr=subprocess.STDOUT,check=False).returncode
            require(status == 0, f'{command[0]} failed (exit {status}); see {log_path}')
        print('Using the existing anatomical registration. Verify its source anatomy shares world coordinates with the FreeSurfer anatomy.',flush=True)
        for h in ('lh','rh'):
            run(['mri_surf2surf','--srcsubject','fsaverage6','--trgsubject','native','--hemi',h,
                 '--sval',out/'inputs'/f'{args.subject}.{h}.fsaverage6.mgh',
                 '--tval',out/'work'/f'{h}.native.mgh','--mapmethod','nnf','--noreshape'])
            values = read_mgh(out/'work'/f'{h}.native.mgh')
            require(values.size == native_n[h], f'{h}: resampled overlay length mismatch.')
            check_labels(values,set(np.unique(labels[h]).tolist())|{0},f'{h} native surface')
        native_volume = out/f'{args.subject}_MSHBM_native.nii.gz'
        command = ['mri_surf2vol','--subject','native']
        for h in ('lh','rh'):
            for surface in ('white','pial'):
                command += ['--so',native/'surf'/f'{h}.{surface}',out/'work'/f'{h}.native.mgh']
        run(command+['--o',native_volume])
        manifest['native_label_counts'] = check_labels(read_nifti(native_volume)['array'],allowed,'Native volume')
        final = out/f'{args.subject}_MSHBM_space-MNI2009.nii.gz'
        run(['3dNwarpApply','-source',native_volume,'-master',reference,
             '-nwarp',f'{warp_local} inputs/affine.aff12.1D','-ainterp','NN','-short','-prefix',final])
        result = read_nifti(final)
        valid_affine(result)
        require(result['shape'][:3] == expected_shape and all(n == 1 for n in result['shape'][3:]), 'Final dimensions differ from the reference.')
        require(np.allclose(result['affine'],expected_affine,rtol=0,atol=1e-4), 'Final affine differs from the reference.')
        manifest['final_label_counts'] = check_labels(result['array'],allowed,'MNI volume')
        manifest['labels_absent_from_final'] = sorted(allowed-{int(v) for v in manifest['final_label_counts']}-{0})
        manifest.update(status='completed',output=str(final)); save_manifest()
        print(f'Created: {final}')
        print('Inspect native cortical coverage and final MNI alignment before analysis.')
        if manifest['labels_absent_from_final']:
            print('Labels absent from final volume:',manifest['labels_absent_from_final'])
        return 0
    except (ValueError,OSError,ET.ParseError,struct.error) as error:
        if out is not None and manifest is not None:
            manifest.update(status='failed',error=str(error))
            (out/f'{args.subject}_run_manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
        print(f'ERROR: {error}',file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
