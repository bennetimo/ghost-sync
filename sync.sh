#!/bin/bash
set -e

if [ -z "$SYNC_HOST" ]; then echo "Error: SYNC_HOST not set. Add it as environment variable with the host to deploy to"; echo "Finished: FAILURE"; exit 1; fi
if [ -z "$SYNC_USER" ]; then echo "Error: SYNC_USER not set. Add it as environment variable with the user to deploy as"; echo "Finished: FAILURE"; exit 1; fi
if [ -z "$SYNC_LOCATION" ]; then echo "Error: SYNC_LOCATION not set. Add it as environment variable with the location to push the files to on the SYNC_HOST. This location should be readable by the ghost-backup container."; echo "Finished: FAILURE"; exit 1; fi

# Directories to sync under (by default) /var/lib/ghost. Turned on with command line flags
usage() { echo "Usage: sync [-d (database)] [-i (images)] [-a (apps)] [-t (themes)]" 1>&2; exit 0; }

database=false
images=false
apps=false
themes=false
sync_dirs=""

GHOST_LOC=
if [ -n "$BACKUP_ENV_GHOST_LOCATION" ]; then 
	# Backup container is linked
	GHOST_LOC=$BACKUP_ENV_GHOST_LOCATION
elif [ -n "$GHOST_LOCATION" ]; then
	GHOST_LOC=$GHOST_LOCATION
else
	GHOST_LOC="/var/lib/ghost"
fi
	
echo "using ghost files from $GHOST_LOC"

syncDatabase () {
	# Test the env that is set if a ghost-backup container is linked
	if [ -z "$BACKUP_NAME" ]; then 
		echo "Error: BACKUP_NAME not set. Have you linked in the ghost-backup container?"
		echo "Finished: FAILURE"; exit 1;
	else
		# Get the name of the backup container (ghost-backup container must be linked with alias 'backup')
		BACKUP_CONTAINER_NAME=`docker inspect -f '{{index .Config.Labels "com.docker.compose.service"}}' $BACKUP_NAME`

		# Take a new snapshot
		echo "Taking a snapshot of the blog: '$BACKUP_CONTAINER_NAME'"
		docker exec $BACKUP_CONTAINER_NAME backup

		# Find the most recent backup (the one we just created)
		#unset -v latest_ghost
		unset -v latest_db
		for file in "$BACKUP_ENV_BACKUP_LOCATION"/*; do
			#[[ $file -nt $latest_ghost  && $file =~ .*ghost* ]] && latest_ghost=$file
			[[ $file -nt $latest_db  && $file =~ .*db* ]] && latest_db=$file
		done

		if [ -z "$latest_db" ]; then 
			echo "Error: Could not access the just created DB snapshot. Have you included the ghost-backup container volumes with --volumes-from?"; 
			echo "Finished: FAILURE"; exit 1
		fi

		echo "copying db file '$latest_db' to $SYNC_HOST:$SYNC_LOCATION"
    	scp $latest_db $SYNC_USER@$SYNC_HOST:$SYNC_LOCATION/sync.db.gz

		echo "updating database"
		ssh $SYNC_USER@$SYNC_HOST "docker exec $BACKUP_CONTAINER_NAME restore -f $SYNC_LOCATION/sync.db.gz && rm $SYNC_LOCATION/sync.db.gz"
	fi
}

syncFiles () {
	echo "updating ghost files"
	rsync -auvz --delete $sync_dirs $SYNC_USER@$SYNC_HOST:$SYNC_LOCATION
}

while getopts "diat" opt; do
  case $opt in
    d) database=true ;;
	i) images=true; sync_dirs="$sync_dirs $GHOST_LOC/images" ;;
	a) apps=true; sync_dirs="$sync_dirs $GHOST_LOC/apps" ;;
	t) themes=true; sync_dirs="$sync_dirs $GHOST_LOC/themes" ;;
    \?) usage; exit 0 ;;
  esac
done

echo "Syncing local ghost to $SYNC_HOST:$SYNC_LOCATION"
echo "Syncing database: $database"
echo "Syncing images: $images"
echo "Syncing apps: $apps"
echo "Syncing themes: $themes"
echo "Sync directories: $sync_dirs"

read -p "Confirm sync y/n: " -r
if [[ $REPLY =~ ^[Yy]$ ]]; then

	if [ $database = true ]; then syncDatabase; fi
	if [ -n "$sync_dirs" ]; then syncFiles; fi
	
	echo "sync complete"
else
	echo "aborted"
fi
