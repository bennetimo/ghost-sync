# ghost-sync

ghost-sync is a [Docker](https://www.docker.com/) container for syncing a [Ghost](https://ghost.org/) blog from a local/dev to remote environment.

It supports syncing the ghost content files (images, apps, themes, settings etc), as well as the database 
if used in conjunction with [bennetimo/ghost-backup](https://github.com/bennetimo/ghost-backup).
 
For file sync, [rsync](http://linux.about.com/library/cmd/blcmdl1_rsync.htm) is used so that only incremental changes need to be copied
to save bandwidth. The remote ghost content folder is made identical to the local.  
 
Database syncing works (either sqlite or mysql/[mariadb](https://hub.docker.com/_/mariadb/)) by using [bennetimo/ghost-backup](https://github.com/bennetimo/ghost-backup)
in order to take a live backup of the local installation, and then restore that backup straight away to the remote.

In this way, the database sync is safe and doesn't involve physically copying over the database files.

### Prerequisites
You have ssh access setup between the local and remote environment.

> For database sync, you also need to configure [bennetimo/ghost-backup](https://github.com/bennetimo/ghost-backup)

### Quick Start

Create and run the ghost-sync container with the volume from your Ghost data container, specifying the remote host details as environment variables. The container also needs ssh access to the remote host, and one way to do that is to mount the appropriate private key. 

For example:

```
docker run -it --rm --volumes-from <your-data-container> \
    -v ~/.ssh/<privatekey>:~/.ssh/id_rsa:ro \
    -e SYNC_HOST=<remotehost> 
    -e SYNC_USER=<remoteuser> 
    -e GHOST_CONTENT_REMOTE=<location> bennetimo/ghost-sync`
```

Where:

 * `<your-data-container>` is where your ghost content lives (your Ghost container or separate data container)
 * `<privatekey>` is the ssh key to connect with your remote host
 * `<remotehost>`: The remote host to sync with
 * `<remoteuser>`: The ssh user for the sync
 * `<location>`: The location to sync the files to (default `/var/lib/ghost/content`)

ghost-sync will then run and by default sync the images (only) under `/var/lib/ghost/images` to the remote host under `GHOST_CONTENT_REMOTE`.

> N.B. The container is run interactively and it asks for a confirmation before actually initiating a sync

### Specifying other folders to sync

By default only the images will be synced, as the docker cmd starts with the `-i` flag. You can override this with the following flags:

| Flag  |  Meaning      |
| ----- | ------------- |
| -c    | Sync all the below |
| -i    | Sync /images 	|
| -t    | Sync /themes  | 
| -a  	| Sync /apps    | 
| -d 	| Sync database |
| -s    | Sync settings |

> In order to sync the database you need to use ghost-sync in conjunction with [bennetimo/ghost-backup](https://github.com/bennetimo/ghost-backup), see below.

For example, to sync the images and database you would use the flags `-id` when starting the container above. 

### Syncing the database
[bennetimo/ghost-backup](https://github.com/bennetimo/ghost-backup) is a container that can take an online backup of the ghost database. If setup, you can use it for an online database sync. It needs to be setup on the local and remote environments.

You need to link in the ghost-backup container, and its volumes

```
docker run -it --rm --link ghost-backup:backup \
 --volumes-from ghost-backup-container 
 --volumes-from your-data-container 
 -v ~/.ssh/yourprivatekey:~/.ssh/id_rsa:ro 
 -v /var/run/docker.sock:/var/run/docker.sock:ro 
 -e SYNC_HOST=<remotehost> 
 -e SYNC_USER=<remoteuser> 
 -e GHOST_CONTENT_REMOTE=<location>
 bennetimo/ghost-sync -d
```
 
> Note the -d flag specified, and the mounting of the docker socket. This is so ghost-sync can execute the `backup` command of the ghost-backup container.

Now when performing a sync the script will:

 1. Initiate a snapshot/backup using the ghost-backup container. 
 1. Copy the database dump generated to the remote host as `backup-ghostsync-temp.db.gz` in the same location as the standard sync
 1. Initiate a restore of the database using the ghost-backup container on the remote host
 1. Remove the `backup-ghostsync-temp.db.gz` file.

> The ghost-backup container needs to have the same name on both the local and remote host.

### Advanced Configuration
ghost-sync has a number of options which can be configured as you need. 

| Environment Variable  | Default       | Meaning           |
| --------------------- | ------------- | ----------------- | 
| SYNC_HOST | N/A   | Remote host IP or hostname |
| SYNC_USER | N/A | Remote host user to connect with |
| BACKUP_LOCATION | N/A | Backup location for ghost-backup files |
| GHOST_CONTENT_LOCAL           | /var/lib/ghost/content   | Location of ghost files to sync (on the local host) |
| GHOST_CONTENT_REMOTE       | /var/lib/ghost/content    | Location to sync local ghost files to on the remote host |
| GHOST_BACKUP_CONTAINER     | ghost-backup             | The name of a linked ghost-backup container (required if you want to sync the database) |
| LOG_LOCATION          | /var/log/ghost-sync.log | Location of the log file |
| BACKUP_FILE_PREFIX    | backup | Prefix to put before the temp synced DB archive so that it is recognised by the remote ghost-backup container |


### Configuring with Docker Compose
If you're using Compose, then you can use a configuration like:

```
sync-blog:
   image: bennetimo/ghost-sync
   container_name: "sync-blog"
   environment:
    - SYNC_HOST=<remotehost>
    - SYNC_USER=<remoteuser>
    - GHOST_CONTENT_REMOTE=<your-remote-ghost-content>
    - GHOST_BACKUP_CONTAINER=<your-ghost-backup-container-name>
    - BACKUP_LOCATION=<your-backup-location>
   entrypoint: "/bin/bash"
   volumes:
    - ~/.ssh/yourprivatekey:/root/.ssh/id_rsa:ro
    - /var/run/docker.sock:/var/run/docker.sock:ro
    - "<your-data-container>:/var/lib/ghost/content"
    - "<your-backup-container>:<your-backup-location>"
```

The entrypoint is overridden in this example so that a sync is not initiated by default.

Instead, with configuration like the above as part of a wider docker-compose setup you might run something
like:

`docker-compose run --rm sync-blog sync -id`
 
### Workflow
Using ghost-sync with image and database sync, you can achieve the following workflow:

 1. Write/edit posts locally
 1. Initiate ghost-sync to push the changes to the remote host
 1. Restart the remote ghost container (to pick up the db changes, not required for static files)

### Under the covers
ghost-sync uses [rsync](http://linux.about.com/library/cmd/blcmdl1_rsync.htm) for transferring the files to the remote server. 



