docker ps -a | awk '/Exited/{print $1}' | xargs docker rm
