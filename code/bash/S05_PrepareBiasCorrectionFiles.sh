set -e

PRJ_DIR=/data/SFIMJGC_CLARID/AKColab/
PRCSDATA_DIR=${PRJ_DIR}prcs_data/
ORIGDATA_DIR=${PRJ_DIR}orig_data/ds007216-download/
OUT_DIR=${PRCSDATA_DIR}${SBJ}/${SES}/D04_BiasField_${RUN}/
ml afni
ml fsl

if [[ -d "${OUT_DIR}" ]]; then rm -rf ${OUT_DIR}; fi

mkdir -p ${OUT_DIR}
cd ${OUT_DIR}

echo "++ Compute Echo Time differences..."
echo "++ ================================"
FMAP_JSON_PATH=${ORIGDATA_DIR}${SBJ}/${SES}/fmap/${SBJ}_${SES}_phasediff.json
delta_te_ms=$(jq -er '
  (.EchoTime1 | numbers) as $te1 |
  (.EchoTime2 | numbers) as $te2 |
  (($te2 - $te1) * 1000) | select(. > 0)
' "${FMAP_JSON_PATH}") || exit 1
echo "++ Echo-Time Difference: ${delta_te_ms} ms."

echo "++ Brain Extraction from magnitude 1 image..."
echo "++ =========================================="
bet ${ORIGDATA_DIR}${SBJ}/${SES}/fmap/${SBJ}_${SES}_magnitude1.nii.gz ${SBJ}_${SES}_magnitude1_brain.nii.gz -R -m
echo "++ Correcting size on brain..."
echo "++ ==========================="
echo "3drefit -copyaux ${ORIGDATA_DIR}${SBJ}/${SES}/fmap/${SBJ}_${SES}_magnitude1.nii.gz ${SBJ}_${SES}_magnitude1_brain.nii.gz"
3drefit -copyaux ${ORIGDATA_DIR}${SBJ}/${SES}/fmap/${SBJ}_${SES}_magnitude1.nii.gz ${SBJ}_${SES}_magnitude1_brain.nii.gz
echo "++ Correcting size on brain mask..."
echo "++ ================================"
echo "3drefit -copyaux ${ORIGDATA_DIR}${SBJ}/${SES}/fmap/${SBJ}_${SES}_magnitude1.nii.gz ${SBJ}_${SES}_magnitude1_brain_mask.nii.gz"
3drefit -copyaux ${ORIGDATA_DIR}${SBJ}/${SES}/fmap/${SBJ}_${SES}_magnitude1.nii.gz ${SBJ}_${SES}_magnitude1_brain_mask.nii.gz

echo "++ Correct phase diff to between 0 and 4095..."
echo "++ ==========================================="
3dcalc -overwrite                                                          \
       -a ${ORIGDATA_DIR}${SBJ}/${SES}/fmap/${SBJ}_${SES}_phasediff.nii.gz \
       -expr '(a+4096)/2'                                                  \
       -datum float                                                        \
       -prefix ${SBJ}_${SES}_phasediff_0to4095.nii.gz

echo "++ Prepare field map with fsl..."
echo "++ =========================================="
fsl_prepare_fieldmap SIEMENS                                \
                     ${SBJ}_${SES}_phasediff_0to4095.nii.gz \
                     ${SBJ}_${SES}_magnitude1_brain.nii.gz  \
                     ${SBJ}_${SES}_fieldmap_rads.nii.gz     \
                     ${delta_te_ms}
 
echo "++ Redo stats in fieldmap..."
echo "++ ========================="
#pwd
#echo "3drefit -redo_bstat ${SBJ}_${SES}_fieldmap_rads.nii.gz"
#3drefit -redo_bstat ${SBJ}_${SES}_fieldmap_rads.nii.gz

echo "++ Prepare WARP file..."
echo "++ ===================="
echo """epi_b0_correct.py -in_freq ${SBJ}_${SES}_fieldmap_rads.nii.gz                                                \
                  -in_magn ${ORIGDATA_DIR}${SBJ}/${SES}/fmap/${SBJ}_${SES}_magnitude1.nii.gz                 \
                  -in_mask ${SBJ}_${SES}_magnitude1_brain_mask.nii.gz                                        \
                  -in_epi ${ORIGDATA_DIR}${SBJ}/${SES}/func/${SBJ}_${SES}_task-${TASK}_${RUN}_bold.nii.gz    \
                  -in_epi_json ${ORIGDATA_DIR}${SBJ}/${SES}/func/${SBJ}_${SES}_task-${TASK}_${RUN}_bold.json \
                  -do_recenter_freq MEAN                                                                     \
                  -prefix ${SBJ}_${SES}_task-${TASK}_${RUN}_bold 
"""
epi_b0_correct.py -in_freq ${SBJ}_${SES}_fieldmap_rads.nii.gz                                                \
                  -in_magn ${ORIGDATA_DIR}${SBJ}/${SES}/fmap/${SBJ}_${SES}_magnitude1.nii.gz                 \
                  -in_mask ${SBJ}_${SES}_magnitude1_brain_mask.nii.gz                                        \
                  -in_epi ${ORIGDATA_DIR}${SBJ}/${SES}/func/${SBJ}_${SES}_task-${TASK}_${RUN}_bold.nii.gz    \
                  -in_epi_json ${ORIGDATA_DIR}${SBJ}/${SES}/func/${SBJ}_${SES}_task-${TASK}_${RUN}_bold.json \
                  -do_recenter_freq MEAN                                                                     \
                  -prefix ${SBJ}_${SES}_task-${TASK}_${RUN}_bold 

