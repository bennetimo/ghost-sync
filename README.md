# ghost-sync

ghost-sync is a [Docker](https://www.docker.com/) container for syncing a [Ghost](https://ghost.org/) blog from a local/dev to remote environment.

It supports syncing the images, apps, and themes. In addition, it can sync the database (either sqlite or mysql/[mariadb](https://hub.docker.com/_/mariadb/)) when used in conjunction with [bennetimo/ghost-backup](https://github.com/bennetimo/ghost-backup). 

### Prerequisites
You have ssh access setup between the local and remote environment.

### Quick Start

Create and run the ghost-sync container with the volume from your Ghost data container, specifying the remote host details as environment variables. The container also needs ssh access to the remote host, and one way to do that is to mount the appropriate private key. 

For example:

`docker run -it --rm --volumes-from <your-data-container> -v ~/.ssh/<privatekey>:~/.ssh/id_rsa -e SYNC_HOST=<host> -e SYNC_USER=<user> -e SYNC_LOCATION=<location> bennetimo/ghost-sync`

Where:

 * `<your-data-container>` is where your ghost themes live (your Ghost container or separate data container)
 * `<privatekey>` is the ssh key to connect with your remote host
 * `<host>`: The remote host to sync with
 * `<user>`: The ssh user for the sync
 * `<location>`: The location to sync the files to (default `/sync`)

ghost-sync will then run and by default sync the images (only) under `/var/lib/ghost/images` to the remote host under `SYNC_LOCATION`.

> The container is run interactive as it asks for a confirmation before initiating a sync

### Specifying other folders to sync

By default only the images will be synced, as the docker cmd starts with the `-i` flag. You can override this with the following flags:

| Flag  |  Meaning      |
| ----- | ------------- |
| -i    | Sync /images 	|
| -t    | Sync /themes  | 
| -a  	| Sync /apps    | 
| -d 	| Sync database |

> In order to sync the database you need to use ghost-sync in conjunction with [bennetimo/ghost-backup](https://github.com/bennetimo/ghost-backup), see below.

For example, to sync the images and database you would use the flags `-id` when starting the container above. 

### Syncing the database
[bennetimo/ghost-backup](https://github.com/bennetimo/ghost-backup) is a container that can take an online backup of the ghost database. If setup, you can use it for an online database sync. 

You need to link in the ghost-backup container, and its volumes

`docker run -it --rm --link ghost-backup:backup --volumes-from ghost-backup-container --volumes-from your-data-container -v ~/.ssh/yourprivatekey:~/.ssh/id_rsa -v /var/run/docker.sock:/var/run/docker.sock:ro -e SYNC_HOST=178.62.43.109 -e SYNC_USER=tim -e SYNC_LOCATION=/sync/upandultra.com bennetimo/ghost-sync -d`

> Note the -d flag specified, and the mounting of the docker socket. This is so ghost-sync can execute the ghost-backup container.

Now when performing a sync the script will:

 1. Initiate a snapshot/backup using the ghost-backup container
 1. Copy the database dump generated to the remote host as `sync.db.gz` in the same location as the standard sync
 1. Initate a restore of the dump using the ghost-backup container on the remote host
 1. Remove the `sync.db.gz` file.

> The ghost-backup container needs to have the same name on both the local and remote host.

### Configuring with Docker Compose
If you're using Compose, then you can use a configuration like:

```
sync-blog:
 image: bennetimo/ghost-sync
 container_name: "sync-blog"
 entrypoint: /bin/bash
 environment:
  - SYNC_HOST=host
  - SYNC_USER=user
  - SYNC_LOCATION=location
 volumes:
  - ~/.ssh/privatekey:/root/.ssh/id_rsa:ro
  - /var/run/docker.sock:/var/run/docker.sock:ro
 volumes_from:
  - your-data-container
  - your-backup-container
 links:
  - your-backup-container:backup
 ```

The entrypoint is overridden so that a `docker-compose up` does not try to initiate a sync. Once the stack is up, you can run a sync with:

`docker-compose run sync-blog sync -i`

### Workflow
Using ghost-sync with image and database sync, you can acheive the following workflow:

 1. Write/edit posts locally
 1. Initate ghost-sync to push the changes to the remote host

You just need to mount the `SYNC_LOCATION/images` directory on the remote host as the Ghost blogs images directory.

`-v $SYNC_LOCATION/images:/var/lib/ghost/images`

Now any images that get rysnc'd from your local environment will be accessible straight away by the remote Ghost. 

### Under the covers
ghost-sync uses [rsync](http://linux.about.com/library/cmd/blcmdl1_rsync.htm) for transfering the files to the remote server. 



