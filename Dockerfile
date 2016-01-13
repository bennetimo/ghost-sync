FROM ubuntu

MAINTAINER Tim Bennett <tim@coderunner.io>

RUN \
  apt-get update && \
  apt-get install -y openssh-client docker.io

# Clean up
RUN apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Add the sync script
COPY sync.sh /bin/sync
RUN chmod +x /bin/sync

ENTRYPOINT ["/bin/bash"]