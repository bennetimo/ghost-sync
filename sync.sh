#!/bin/bash
set -e

# Simple log, write to stdout
log () {
    echo "`date -u`: $1" | tee -a $LOG_LOCATION
}

if [ -z "$SYNC_HOST" ]; then log "Error: SYNC_HOST not set. Add it as environment variable with the host to deploy to"; log "Finished: FAILURE"; exit 1; fi
if [ -z "$SYNC_USER" ]; then log "Error: SYNC_USER not set. Add it as environment variable with the user to deploy as"; log "Finished: FAILURE"; exit 1; fi
if [ -z "$GHOST_CONTENT_REMOTE" ]; then log "Error: GHOST_CONTENT_REMOTE not set. Add it as environment variable with the location to push the files to on the SYNC_HOST. This location should be readable by the ghost-backup container."; log "Finished: FAILURE"; exit 1; fi

# Directories to sync under (by default) /var/lib/ghost/content. Turned on with command line flags
usage() { log "Usage: sync [-c (all content and db)] [-d (database)] [-i (images)] [-a (apps)] [-t (themes)] [-s (settings)]" 1>&2; exit 0; }

database=false
images=false
apps=false
themes=false
settings=false
sync_dirs=""

syncDatabase () {
	log "Checking that the ghost-backup container is available with name: $GHOST_BACKUP_CONTAINER"

	if [[ $(docker ps --filter "name=^/$GHOST_BACKUP_CONTAINER$" --format '{{.Names}}') == $GHOST_BACKUP_CONTAINER ]]; then
	    log " ...OK"
	else
	    log "Error: $GHOST_BACKUP_CONTAINER not found. Set \$GHOST_BACKUP_CONTAINER to the name of your ghost-backup container"
		log "Finished: FAILURE"; exit 1;
	fi

	# Test the env that is set if a ghost-backup container is linked
	if [ -z "$BACKUP_LOCATION" ]; then
		log "Error: \$BACKUP_LOCATION not set. Set this to the location of the your backup files generated from ghost-backup"
		log "Finished: FAILURE"; exit 1;
	fi

    # Take a new snapshot
    log "Taking a snapshot of the blog via container '$GHOST_BACKUP_CONTAINER'"
    docker exec $GHOST_BACKUP_CONTAINER backup

    # Find the most recent backup (the one we just created)

    log "Finding the just created db archive backup"
    DB_ARCHIVE_MATCH="${BACKUP_FILE_PREFIX}.*db.*gz"

    unset -v latest_db
    for file in "$BACKUP_LOCATION"/*; do
        [[ $file -nt $latest_db  && $file =~ .*$DB_ARCHIVE_MATCH.* ]] && latest_db=$file
    done

    if [ -z "$latest_db" ]; then
        log "Error: Could not access the just created DB snapshot. Have you mounted the ghost-backup container volumes?";
        log "Finished: FAILURE"; exit 1
    fi

    TEMP_DB_ARCHIVE="${BACKUP_FILE_PREFIX}-ghostsync-temp.db.gz"

    log "Copying db archive file '$latest_db' to $SYNC_HOST:$GHOST_CONTENT_REMOTE as '$TEMP_DB_ARCHIVE'"
    scp $latest_db $SYNC_USER@$SYNC_HOST:$GHOST_CONTENT_REMOTE/$TEMP_DB_ARCHIVE
    log "...OK"

    log "updating database on remote host via ghost-backup restore"
    # N.B. When calling restore here we use the file path from the *local* system, because that's what  we've just mirrored to the remote
    # i.e. on the remote host $GHOST_CONTENT_LOCAL should be the same mount point that we synced to as $GHOST_CONTENT_REMOTE
    ssh $SYNC_USER@$SYNC_HOST "docker exec $GHOST_BACKUP_CONTAINER restore -f $GHOST_CONTENT_LOCAL/$TEMP_DB_ARCHIVE && rm $GHOST_CONTENT_REMOTE/$TEMP_DB_ARCHIVE"
    log "...OK"
}

syncFiles () {
	log "syncing ghost content files from local to remote"
	rsync -auvz --delete $sync_dirs $SYNC_USER@$SYNC_HOST:$GHOST_CONTENT_REMOTE
	log "...OK"
}

while getopts "cdiats" opt; do
  case $opt in
    c)
      database=true
      images=true
      apps=true
      themes=true
      settings=true
      sync_dirs="$GHOST_CONTENT_LOCAL/images $GHOST_CONTENT_LOCAL/apps $GHOST_CONTENT_LOCAL/themes $GHOST_CONTENT_LOCAL/settings"
      ;;
    d) database=true ;;
	i) images=true; sync_dirs="$sync_dirs $GHOST_CONTENT_LOCAL/images" ;;
	a) apps=true; sync_dirs="$sync_dirs $GHOST_CONTENT_LOCAL/apps" ;;
	t) themes=true; sync_dirs="$sync_dirs $GHOST_CONTENT_LOCAL/themes" ;;
	s) settings=true; sync_dirs="$sync_dirs $GHOST_CONTENT_LOCAL/settings" ;;
    \?) usage; exit 0 ;;
  esac
done

log "*******************************************************************************************************"
log "Syncing local ghost files at $GHOST_CONTENT_LOCAL to $SYNC_HOST:$GHOST_CONTENT_REMOTE"
log "   Database syncing requires a bennetimo/ghost-backup container running on both local and remote"
log "   Ghost content files sync happens via rsync directly from local to remote"
log "*******************************************************************************************************"
log "Syncing database: $database (ghost-backup container set to: $GHOST_BACKUP_CONTAINER)"
log "Syncing images: $images"
log "Syncing apps: $apps"
log "Syncing themes: $themes"
log "Syncing settings: $settings"
log "*******************************************************************************************************"
log "Sync directories: $sync_dirs"
log "*******************************************************************************************************"

log "*** CHECK THAT THE ABOVE IS CORRECT BEFORE SYNCING ***"
read -p "Confirm sync y/n: " -r
if [[ $REPLY =~ ^[Yy]$ ]]; then

	if [ $database = true ]; then syncDatabase; fi
	if [ -n "$sync_dirs" ]; then syncFiles; fi
	
	log "sync completed successfully. (restart your blog container to reflect the changes if you updated the database)"
else
	log "aborted"
fi
