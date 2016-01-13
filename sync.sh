#!/bin/bash
set -e

if [ -z "$SYNC_HOST" ]; then echo "Error: SYNC_HOST not set. Add it as environment variable with the host to deploy to"; echo "Finished: FAILURE"; exit 1; fi
if [ -z "$SYNC_USER" ]; then echo "Error: SYNC_USER not set. Add it as environment variable with the user to deploy as"; echo "Finished: FAILURE"; exit 1; fi
if [ -z "$SYNC_LOCATION" ]; then echo "Error: SYNC_LOCATION not set. Add it as environment variable with the location to push the files to on the SYNC_HOST. This location should be readable by the ghost-backup container."; echo "Finished: FAILURE"; exit 1; fi

echo "Syncing local ghost with $SYNC_HOST"

# Get the name of the backup container (ghost-backup container must be linked with alias 'backup')
BACKUP_CONTAINER_NAME=`docker inspect -f '{{index .Config.Labels "com.docker.compose.service"}}' $BACKUP_NAME`

# Take a new snapshot
echo "Taking a snapshot of the blog: '$BACKUP_CONTAINER_NAME'"
docker exec $BACKUP_CONTAINER_NAME backup

# Find the most recent backup (the one we just created)
unset -v latest_ghost
unset -v latest_db
for file in "$BACKUP_ENV_BACKUP_LOCATION"/*; do
	[[ $file -nt $latest_ghost  && $file =~ .*ghost* ]] && latest_ghost=$file
	[[ $file -nt $latest_db  && $file =~ .*db* ]] && latest_db=$file
done

echo "Will sync ghost archive: $latest_ghost" 
echo "Will sync ghost db snapshot: $latest_db" 

read -p "Really sync to $SYNC_HOST? y/n: " -r
if [[ $REPLY =~ ^[Yy]$ ]]
then
    echo "connecting to $SYNC_HOST..."
    echo " copying ghost files to $SYNC_HOST:$SYNC_LOCATION"
    scp $latest_ghost $SYNC_USER@$SYNC_HOST:$SYNC_LOCATION/sync.ghost.gz

    echo " copying db file to $SYNC_HOST:$SYNC_LOCATION"
    scp $latest_db $SYNC_USER@$SYNC_HOST:$SYNC_LOCATION/sync.db.gz

    #echo "rsyncing images to $SYNC_HOST:$SYNC_LOCATION/images"
    #rsync -avz $BACKUP_ENV_GHOST_LOCATION/images $BACKUP_ENV_GHOST_LOCATION/themes $latest_db $SYNC_USER@$SYNC_HOST:$SYNC_LOCATION
    echo " updating database..."
    ssh $SYNC_USER@$SYNC_HOST "docker exec $BACKUP_CONTAINER_NAME restore -F $SYNC_LOCATION/sync.db.gz" 

    echo " updating ghost files..."
    ssh $SYNC_USER@$SYNC_HOST "docker exec $BACKUP_CONTAINER_NAME restore -F $SYNC_LOCATION/sync.ghost.gz" 

    echo "sync complete"
fi