**********************
Harbor run as non-root
**********************

0. 更新/etc/rc.d/rc.local，添加一下内容，并确保/etc/rc.d/rc.local具有可执行权限:

::

	docker-compose -f /path/to/harbor/docker-compose.yml down
	docker-compose -f /path/to/harbor/docker-compose.yml up -d

1. 重新制作harbor-log镜像:

1.1 vi Dockerfile:

::

	FROM goharbor/harbor-log:v1.9.2
	ADD start.sh /usr/local/bin/start.sh
	USER 10000:10000
	CMD ["/bin/sh", "-c", "/usr/local/bin/start.sh"]

1.2 vi start.sh

::

	#!/bin/bash
	crond
	rsyslogd -n

1.3

::

	chown 10000:10000 start.sh
	chmod +x start.sh
	docker build . -t secure-harbor-log:v1.9.2

2. 重新制作registry镜像:

2.1 vi Dockerfile:

::

	FROM goharbor/registry-photon:v2.7.1-patch-2819-2553-v1.9.2
	ADD entrypoint.sh /entrypoint.sh
	RUN chown -R 10000:10000 /var/lib/registry
	USER 10000:10000
	CMD ["sh", "/entrypoint.sh", "/etc/registry/config.yml"]

2.2 vi entrypoint.sh:

::

	#!/bin/sh

	# chown 10000:10000 /var/lib/registry
	# chown 10000:10000 -R /storage
	/harbor/install_cert.sh
	registry serve /etc/registry/config.yml

2.3

::
	chown 10000:10000 entrypoint.sh
	chmod +x entrypoint.sh
	docker build . -t secure-registry-photon:v2.7.1-patch-2819-2553-v1.9.2

3. 重新制作registryctl镜像:

3.1 vi Dockerfile:

::

	FROM goharbor/harbor-registryctl:v1.9.2
	ADD start.sh /harbor/start.sh
	RUN chown -R 10000:10000 /var/lib/registry
	USER 10000:10000
	CMD ["sh", "/harbor/start.sh"]

3.2 vi start.sh:

::

	#!/bin/sh

	# chown 10000:10000 -R /var/lib/registry
	# chown 10000:10000 -R /storage
	/harbor/install_cert.sh
	/harbor/harbor_registryctl -c /etc/registryctl/config.yml

3.3

::

	chown 10000:10000 start.sh
	chmod +x start.sh
	docker build . -t secure-harbor-registryctl:v1.9.2

4. 重新chartmuseum镜像

4.1 vi Dockerfile

::

	FROM goharbor/chartmuseum-photon:v0.9.0-v1.9.2
	ADD docker-entrypoint.sh /docker-entrypoint.sh
	USER 10000:10000
	CMD ["bash", "/docker-entrypoint.sh"]

4.2 vi docker-entrypoint.sh

::

	#!/bin/bash

	# chown 10000:10000 -R /chart_storage
	/harbor/install_cert.sh
	/chartserver/chartm

4.3

::

	chmod +x docker-entrypoint.sh 
	chown 10000:10000 docker-entrypoint.sh 
	docker build . -t secure-chartmuseum-photon:v0.9.0-v1.9.2 

5. 重新制作clair镜像

5.1 vi Dockerfile

::

	FROM goharbor/clair-photon:v2.0.9-v1.9.2
	ADD docker-entrypoint.sh /docker-entrypoint.sh
	USER 10000:10000
	CMD ["bash", "/docker-entrypoint.sh"]

5.2 vi docker-entrypoint.sh

::

	#!/bin/bash

	/harbor/install_cert.sh
	/dumb-init -- /clair/clair -config /etc/clair/config.yaml


5.3 

::

	chmod +x docker-entrypoint.sh 
	chown 10000:10000 docker-entrypoint.sh 
	docker build . -t secure-clair-photon:v2.0.9-v1.9.2

6. 确认路径的owner

::

	# log
	chown -R 10000:10000 /var/log/harbor

	# registry, registryctl
	chown -R 10000:10000 </path/to/harbor/data>/registry

	# chartmuseum
	chown -R 10000:10000 </path/to/harbor/data>/chart_storage

7. 修改docker-compose.yml，添加(+)号开始的行，删除(-)开始的行:

::

   # 先备份！！！
   cp docker-compose.yml docker-compose.yml.bak

   # 编辑docker-compose.yml
   log:
   (-) image: goharbor/harbor-log:v1.9.2
   (+) image: secure-harbor-log:v1.9.2
   (-) cap_add:
   (-)  - CHOWN
   (-)  - DAC_OVERRIDE
   (-)  - SETGID
   (-)  - SETUID

   registry:
   (-) image: goharbor/registry-photon:v2.7.1-patch-2819-2553-v1.9.2
   (+) image: secure-registry-photon:v2.7.1-patch-2819-2553-v1.9.2
   (-) cap_add:
   (-)   - CHOWN
   (-)   - SETGID
   (-)   - SETUID

   registryctl:
   (-) image: goharbor/harbor-registryctl:v1.9.2
   (+) image: secure-harbor-registryctl:v1.9.2
   (-) cap_add:
   (-)   - CHOWN
   (-)   - SETGID
   (-)   - SETUID

   chartmuseum:
   (-) image: goharbor/chartmuseum-photon:v0.9.0-v1.9.2
   (+) image: secure-chartmuseum-photon:v0.9.0-v1.9.2
   (-) cap_add:
   (-)   - CHOWN
   (-)   - DAC_OVERRIDE
   (-)   - SETGID
   (-)   - SETUID

   // 如果当前环境enable了clair
   clair:
   (-) image: goharbor/clair-photon:v2.0.9-v1.9.2
   (+) image: secure-clair-photon:v2.0.9-v1.9.2
   (-) cap_add:
   (-)   - DAC_OVERRIDE
   (-)   - SETGID
   (-)   - SETUID

   postgresql:
   // 注意: 以下使用999 user:group的组件还包括redis, clair-db
   // 在harbor数据目录下ls -l可以查看到polkitd ssh_keys的user和group
   // 一般对应999，可以通过查看/etc/passwd和/etc/group确认
   (+) user: "999:999"
   (-) cap_add:
   (-)   - CHOWN
   (-)   - DAC_OVERRIDE
   (-)   - SETGID
   (-)   - SETUID

   core:
   (+) user: "10000:10000"
   (-) cap_add:
   (-)   - SETGID
   (-)   - SETUID

   portal:
   (+) user: "10000:10000"
   (-) cap_add:
   (-)   - CHOWN
   (-)   - SETGID
   (-)   - SETUID

   jobservice:
   (+) user: "10000:10000"
   (-) cap_add:
   (-)   - CHOWN
   (-)   - SETGID
   (-)   - SETUID

   redis:
   (+) user: "999:999"
   (-) cap_add:
   (-)   - CHOWN
   (-)   - SETGID
   (-)   - SETUID

   proxy:
   (+) user: "10000:10000"
       cap_add:
   (-)   - CHOWN
   (-)   - SETGID
   (-)   - SETUID

   // 如果当前环境enable了clair，并且使用clair-db
   clair-db:
   (+) user: "999:999"
   (-) cap_add:
   (-)   - CHOWN
   (-)   - DAC_OVERRIDE
   (-)   - SETGID
   (-)   - SETUID

8.

::

	docker-compose down
	docker-compose up -d
