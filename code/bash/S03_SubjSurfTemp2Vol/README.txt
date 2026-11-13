Reusable fsaverage6 cortical labels -> subject anatomy -> MNI2009c
================================================================

This version takes each subject's CIFTI dense-label file (.dlabel.nii),
subject ID, existing FreeSurfer reconstruction, and matching SSwarper
outputs. It extracts fresh labels on EVERY run. No sub-001 label data is
used unless you supply sub-001's CIFTI as --dlabel.

The file called '.dfile.nii' in the conversation is the .dlabel.nii CIFTI
label file. Contents, not just the extension, are checked.

Requirements
------------
- Python 3.9+ and NumPy (python3 -m pip install numpy, if needed).
- FreeSurfer configured, with mri_surf2surf and mri_surf2vol on PATH.
- AFNI configured, with 3dNwarpApply on PATH.
- The participant's completed FreeSurfer reconstruction: bilateral
  sphere.reg, white and pial surfaces, plus mri/orig.mgz and mri/ribbon.mgz.
- The real fsaverage6 template (40,962 vertices per hemisphere).
- The matching SSwarper affine AND nonlinear warp to MNI2009c.

Neuromaps, NiBabel and Connectome Workbench are not required. Neuromaps
provides no surface-to-volume transform; this workflow uses FreeSurfer
and AFNI for that projection.

Run one subject
---------------
After extracting this ZIP, run the following from its extracted directory.
Replace the example paths with your project paths. Do not create --out-dir
in advance: it must be a new directory to prevent overwriting results.

bash run_with_native_registration.sh \
  --dlabel /data/parcellations/sub-002_fsaverage6_MSHBM_parcellation.dlabel.nii \
  --subject sub-002 \
  --subjects-dir /data/freesurfer/subjects \
  --sswarper-dir /data/sswarper/sub-002 \
  --out-dir /data/volumetric_parcellations/sub-002

The script finds these two files inside --sswarper-dir:
  anatQQ.sub-002_WARP.nii  OR  anatQQ.sub-002_WARP.nii.gz
  anatQQ.sub-002.aff12.1D

It defaults to the included MNI2009_ref.nii.gz, extracted from sub-brick 0
of your MNI152_2009_template_SSW.nii.gz. It is shared across subjects and
has a 193 x 229 x 193 grid at 1 mm. To read your original template directly,
add:
  --template /data/templates/MNI152_2009_template_SSW.nii.gz

The selected template MUST be in the same MNI2009 space targeted by your
SSwarper run. --template sets the output grid; it does not register between
different MNI variants. This package's output naming assumes MNI2009.

If SSwarper filenames differ
---------------------------
Replace --sswarper-dir with BOTH of these options:
  --warp /data/sswarper/sub-002/anatQQ.sub-002_WARP.nii.gz \
  --affine /data/sswarper/sub-002/anatQQ.sub-002.aff12.1D

Supply the nonlinear _WARP file, not anatQQ.<subject>.nii (the warped T1).
The script applies the combination in this AFNI order:
  -nwarp 'nonlinear_WARP affine.aff12.1D'
Source labels use -ainterp NN to retain integer IDs.

Subject IDs and FreeSurfer templates
-----------------------------------
--subject controls SSwarper filename lookup and all subject output names.
If your FreeSurfer folder is named differently, add:
  --fs-subject your_reconstruction_folder_name

--subjects-dir can be omitted if SUBJECTS_DIR is already set.
fsaverage6 is looked up in this order:
  1. --fsaverage6-dir, if explicitly supplied;
  2. SUBJECTS_DIR/fsaverage6;
  3. FREESURFER_HOME/subjects/fsaverage6.

If it is elsewhere, add --fsaverage6-dir /path/to/actual/fsaverage6.
If it is not installed, obtain the actual fsaverage6 template once and use
that option. Do not rename or link full-resolution fsaverage as fsaverage6.
Their vertex counts differ. You do not need to rerun recon-all solely
because fsaverage6 is missing: the existing subject's sphere.reg is used
for resampling. The script creates private template/subject symlinks under
the output directory without changing your FreeSurfer subjects directory.

Essential anatomical-coordinate requirement
------------------------------------------
The FreeSurfer reconstruction and the anatomy used to estimate the SSwarper
transforms must represent the same participant and share world coordinates.
Different voxel grids alone are not a problem. A different scan, a shifted
origin, or edited orientation/obliquity headers can require an additional
registration before applying these transforms. That registration is NOT
estimated by this script. Matching subject IDs cannot establish alignment.

Use your reconstruction and registration provenance to check this condition.
Inspect the native map on the participant's anatomy and the final map on
MNI2009_ref.nii.gz; check both hemispheres and cortical coverage. Automatic
checks validate labels and grid geometry, not anatomical accuracy. Small
parcels can disappear through resampling.

What the script does
--------------------
1. Reads the selected CIFTI map and scatters values using each hemisphere's
   VertexIndices; omitted vertices become background.
2. Writes fresh subject-specific left/right MGH overlays and a label table.
3. Resamples labels to the participant surface using mri_surf2surf
   --mapmethod nnf to avoid averaging network IDs.
4. Uses mri_surf2vol with white/pial surfaces and ribbon.mgz to create a
   conformed native cortical volume.
5. Applies that subject's SSwarper warp and affine to the reference grid
   using nearest-neighbor interpolation for the label image.
6. Checks for noninteger/new labels, all-background output and an incorrect
   final grid; records counts and any IDs missing from the final map.

Supported inputs
----------------
- CIFTI-2 dense labels, both cortical hemispheres in fsaverage6 space,
  40,962 total surface vertices each (included vertices can be sparse).
  The vertex count alone cannot establish registration or correct ordering;
  the input must actually have been generated in fsaverage6 space.
- Cortical-only input; mixed cortical/subcortical files are rejected.
- Integer IDs 0..32767, with 0 reserved for background; names and colors
  come from the current input, not a fixed 17-network table.
- Multi-map dlabels require --map-index N (zero-based).
- Single-file NIfTI-1/2 references and warps, optionally gzip-compressed,
  with a valid spatial sform; AFNI HEAD/BRIK inputs are not supported.
- Scalar and time-series CIFTIs (.dscalar/.dtseries) are not supported.

Outputs for sub-002
-------------------
sub-002_MSHBM_native.nii.gz          Native cortical label volume.
sub-002_MSHBM_space-MNI2009.nii.gz  Final MNI2009 cortical label volume.
sub-002_network_labels.tsv          Current input's names, IDs and RGBA colors.
sub-002_run_manifest.json           Input paths/hash, commands, grid, counts,
                                   status and error details, if any.
sub-002_pipeline.log                FreeSurfer/AFNI command output.
inputs/                            Extracted overlays/reference and warp links.
work/                              Native surface overlays and private links.

Only use the final volume after the command exits successfully and the
manifest status is 'completed'. A failure can leave intermediate files.
Correct the issue and rerun into a NEW output directory.

Preparation without FreeSurfer/AFNI
----------------------------------
bash run_with_native_registration.sh \
  --dlabel /data/parcellations/sub-002_fsaverage6_MSHBM_parcellation.dlabel.nii \
  --subject sub-002 \
  --out-dir /data/prepared/sub-002 \
  --prepare-only

This extracts labels and the reference only. It produces NO native or MNI
parcellation, and does not validate reconstruction or SSwarper inputs.
Use another new output directory for the full run.

Run multiple subjects (example layout)
-------------------------------------
for subject in sub-001 sub-002 sub-003; do
  bash run_with_native_registration.sh \
    --dlabel "/data/parcellations/${subject}_fsaverage6_MSHBM_parcellation.dlabel.nii" \
    --subject "$subject" \
    --subjects-dir /data/freesurfer/subjects \
    --sswarper-dir "/data/sswarper/$subject" \
    --out-dir "/data/volumetric_parcellations/$subject" || break
done

Package contents and validation
-------------------------------
project_labels.py and run_with_native_registration.sh are reusable code.
MNI2009_ref.nii.gz is the shared reference.
examples/sub-001/ holds the ORIGINAL subject-specific MGH/GIFTI examples,
label table and validation records. The script never reads that folder.
Keep the Python file and reference beside the shell launcher.

The updated extraction ran on your uploaded sub-001 CIFTI and full SSW
template: every extracted label matched the prior verified extraction, and
reference intensities matched original sub-brick 0 with the same sform.
The arrays have 40,962 vertices per hemisphere; nonzero counts are 37,476
left and 37,471 right, with IDs 0..17.

Seven regression tests passed: sparse/reordered brain models, swapped
CIFTI axes and byte order, multi-map selection, invalid inputs, subject
extraction, overwrite prevention, reference geometry, template discovery,
command assembly and failed-command handling.
Run: python3 -m unittest -v test_project_labels.py

External commands are simulated in the orchestration tests. FreeSurfer,
AFNI and the actual subject reconstruction/warps were unavailable here.
The full spatial projection has NOT been run or anatomically validated
here. This ZIP includes no converted MNI map.

Documentation
-------------
https://neuromaps-main.readthedocs.io/en/stable/user_guide/transformations.html
https://surfer.nmr.mgh.harvard.edu/fswiki/mri_surf2surf
https://surfer.nmr.mgh.harvard.edu/fswiki/mri_surf2vol
https://afni.nimh.nih.gov/pub/dist/doc/program_help/@SSwarper.html
https://afni.nimh.nih.gov/pub/dist/doc/program_help/3dNwarpApply.html
