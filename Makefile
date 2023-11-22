# Run `make help` to show usage
.DEFAULT_GOAL := help

HOSTNAME ?= $(shell hostname)
# HOSTNAME is the name of the physical host
export HOSTNAME := $(HOSTNAME)

HOST_IP ?= $(shell ip --json route get 1 | jq -r .[0].prefsrc)
NODE_NAME ?= u7s-$(HOSTNAME)
NODE_SUBNET ?= $(shell $(CURDIR)/Makefile.d/node_subnet.sh)
# U7S_HOST_IP is the IP address of the physical host. Accessible from other hosts.
export U7S_HOST_IP := $(HOST_IP)
# U7S_NODE_NAME is the IP address of the Kubernetes node running in Rootless Docker.
# Not accessible from other hosts.
export U7S_NODE_NAME:= $(NODE_NAME)
# U7S_NODE_NAME is the subnet of the Kubernetes node running in Rootless Docker.
# Not accessible from other hosts.
export U7S_NODE_SUBNET := $(NODE_SUBNET)

CONTAINER_ENGINE ?= $(shell $(CURDIR)/Makefile.d/detect_container_engine.sh CONTAINER_ENGINE)
export CONTAINER_ENGINE := $(CONTAINER_ENGINE)

CONTAINER_ENGINE_TYPE ?= $(shell $(CURDIR)/Makefile.d/detect_container_engine.sh CONTAINER_ENGINE_TYPE)
export CONTAINER_ENGINE_TYPE := $(CONTAINER_ENGINE_TYPE)

COMPOSE ?= $(shell $(CURDIR)/Makefile.d/detect_container_engine.sh COMPOSE)

NODE_SERVICE_NAME := node
NODE_SHELL := $(COMPOSE) exec \
	-e U7S_HOST_IP=$(U7S_HOST_IP) \
	-e U7S_NODE_NAME=$(U7S_NODE_NAME) \
	-e U7S_NODE_SUBNET=$(U7S_NODE_SUBNET) \
	$(NODE_SERVICE_NAME)

.PHONY: help
help:
	@echo '# Bootstrap a cluster'
	@echo 'make up'
	@echo 'make kubeadm-init'
	@echo 'make install-flannel'
	@echo
	@echo '# Enable kubectl'
	@echo 'make kubeconfig'
	@echo 'export KUBECONFIG=$$(pwd)/kubeconfig'
	@echo 'kubectl get pods -A'
	@echo
	@echo '# Multi-host'
	@echo 'make join-command'
	@echo 'scp join-command another-host:~/usernetes'
	@echo 'ssh another-host make -C ~/usernetes up kubeadm-join'
	@echo
	@echo '# Debug'
	@echo 'make logs'
	@echo 'make shell'
	@echo 'make down-v'
	@echo 'kubectl taint nodes --all node-role.kubernetes.io/control-plane-'

.PHONY: check-preflight
check-preflight:
	./Makefile.d/check-preflight.sh

.PHONY: up
up: check-preflight
	$(COMPOSE) up --build -d

.PHONY: down
down:
	$(COMPOSE) down

.PHONY: down-v
down-v:
	$(COMPOSE) down -v

.PHONY: rm
rm:
	$(COMPOSE) rm

.PHONY: shell
shell:
	$(NODE_SHELL) bash

.PHONY: logs
logs:
	$(NODE_SHELL) journalctl --follow --since="1 day ago"

.PHONY: kubeconfig
kubeconfig:
	$(COMPOSE) exec -T $(NODE_SERVICE_NAME) cat /etc/kubernetes/admin.conf >kubeconfig
	@echo "# Run the following command by yourself:"
	@echo "export KUBECONFIG=$(shell pwd)/kubeconfig"
ifeq ($(shell command -v kubectl 2> /dev/null),)
	@echo "# To install kubectl, run the following command too:"
	@echo "make kubectl"
endif

.PHONY: kubectl
kubectl:
	$(COMPOSE) exec -T --workdir=/usr/bin $(NODE_SERVICE_NAME) tar c kubectl | tar xv
	@echo "# Run the following command by yourself:"
	@echo "export PATH=$(shell pwd):\$$PATH"
	@echo "source <(kubectl completion bash)"

.PHONY: join-command
join-command:
	$(NODE_SHELL) kubeadm token create --print-join-command | tr -d '\r' >join-command
	@echo "# Copy the 'join-command' file to another host, and run 'make kubeadm-join' on that host (not on this host)"

.PHONY: kubeadm-init
kubeadm-init:
	$(NODE_SHELL) sh -euc "envsubst </usernetes/kubeadm-config.yaml >/tmp/kubeadm-config.yaml"
	$(NODE_SHELL) kubeadm init --config /tmp/kubeadm-config.yaml --skip-token-print
	@echo "# Run 'make join-command' to print the join command"

.PHONY: kubeadm-join
kubeadm-join:
	$(NODE_SHELL) sh -euc '$$(cat /usernetes/join-command)'

.PHONY: install-flannel
install-flannel:
	$(NODE_SHELL) kubectl apply -f /usernetes/manifests/kube-flannel.yml
