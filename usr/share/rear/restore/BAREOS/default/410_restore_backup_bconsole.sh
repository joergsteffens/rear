#
# Restore from Bareos using bconsole (optional)
#

if [ "$BAREOS_RESTORE_MODE" != "bconsole" ]; then
    return
fi

# get last restore jobid before starting the restore
local last_restore_jobid_old
last_restore_jobid_old=$(get_last_restore_jobid)

echo "status client=$BAREOS_CLIENT" | bconsole > "$TMP_DIR/bareos_client_status_before_restore.txt"
LogPrint "$(cat "$TMP_DIR/bareos_client_status_before_restore.txt")"

LogPrint "target_fs_used_disk_space=$(total_target_fs_used_disk_space)"

RESTORE_CMD="restore client=$BAREOS_CLIENT $RESTOREJOB $FILESET where=$TARGET_FS_ROOT select all done yes"

UserOutput ""
UserOutput "The system is now ready for a restore via Bareos."
UserOutput ""
UserOutput "When choosing 'automatic' a Bareos restore without user interaction"
UserOutput "will be started with following options:"
UserOutput "${RESTORE_CMD}"
UserOutput ""
UserOutput "When choosing 'manual', bconsole will be started"
UserOutput "and let you choose the restore options yourself."
UserOutput "Keep in mind, that the new root is mounted under '$TARGET_FS_ROOT',"
UserOutput "so use where=$TARGET_FS_ROOT on restore."
UserOutput "The bconsole history contains the preconfigured restore command."
UserOutput ""

bareos_recovery_mode="$( UserInput -I BAREOS_RECOVERY_MODE -p "Choose restore mode: " -D "automatic" "automatic" "manual" )"

if [ "$bareos_recovery_mode" == "manual" ]; then

    #  fill bconsole history
    cat <<EOF >~/.bconsole_history
exit
list jobs client=$BAREOS_CLIENT jobtype=R
list backups client=$BAREOS_CLIENT
status client=$BAREOS_CLIENT
restore client=$BAREOS_CLIENT $FILESET $RESTOREJOB where=$TARGET_FS_ROOT
restore client=$BAREOS_CLIENT $FILESET $RESTOREJOB where=$TARGET_FS_ROOT select all done
EOF

    if bconsole 0<&6 1>&7 2>&8 ; then
        Log "bconsole finished with zero exit code"
    else
        Log "bconsole finished with non-zero exit code $?"
    fi

else
    # bareos_recovery_mode == automatic: restore most recent backup automatically
    
    LogPrint "starting restore using bconsole:"
    LogPrint "$RESTORE_CMD"

    local restore_cmd_output
    restore_cmd_output=$( bcommand "$RESTORE_CMD" )
    Log "$restore_cmd_output"
fi

LogPrint "waiting for restore job"

local restore_jobid
if ! restore_jobid=$(wait_for_newer_restore_job_to_start "$last_restore_jobid_old"); then
    Error "Restore Job did not start!"
fi
wait_restore_job "$restore_jobid"
local job_exitcode=$?
LogPrint "Restore job $restore_jobid finished."
if [ ${job_exitcode} -eq 0 ]; then
    Log "$( bcommand "list joblog jobid=$restore_jobid" )"
    LogPrint "Restore job finished successfully."
elif [ ${job_exitcode} -eq 1 ]; then
    Log "$( bcommand "list joblog jobid=$restore_jobid" )"
    LogPrint "WARNING: Restore job finished with warnings."
else
    LogPrint "$( bcommand "list joblog jobid=$restore_jobid" )"
    Error "Bareos Restore failed (${job_exitcode})"
fi
