# bak for rpms_and_files/install_kubectl_completion.sh
yum install -y bash-completion
echo 'source /usr/share/bash-completion/bash_completion' >> ~/.bashrc
source ~/.bashrc
echo 'source <(kubectl completion bash)' >>~/.bashrc
source ~/.bashrc
echo "you may need a logout"
