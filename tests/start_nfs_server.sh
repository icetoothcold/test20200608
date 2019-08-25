nfs_server_id=`docker ps -f name=nfs -q`
if test -z $nfs_server_id; then
    nfs_server_id=`docker ps -a -f name=nfs -q`
    if test -z $nfs_server_id; then
        docker run -d --name nfs --privileged -v /home/zongkai/nfs_data:/data -e SHARED_DIRECTORY=/data -p 2049:2049 -e PERMITTED="192.168.100.*" itsthenetwork/nfs-server-alpine:latest
    else
        docker start $nfs_server_id
    fi
    for i in {3..1}; do
        echo "$i..."
        sleep 1
    done
    echo "nfs server started"
else
    echo "nfs server is running"
fi
