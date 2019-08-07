docker rm -f ntp
docker run --name ntp -d -p 123:123/udp lfkeitel/ntpd
