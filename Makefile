MY_NAME_IS := VDL
HERE := $$(pwd)
THIS_FILE := $(lastword $(MAKEFILE_LIST))
UNAME := $$(uname)
VDL_AUDIT_LOGS = ./containers/vdl_node_?/logs/*
VDL_DATA = ./containers/vdl_node_?/data/*
VDL_INIT = ./.vdl_node_1_init
VDL_LOG_FILE = ./vdl.log

default: all

all: prerequisites provision vault_status unseal_nodes audit_device done

stage: prerequisites provision done-stage

telemetry-stack:
	@echo "$(MY_NAME_IS) Grafana and Prometheus telemetry"
	@cd prometheus && make
	@cd grafana && make

load-test:
	@echo "$(MY_NAME_IS) Vault Benchmark load test"

done:
	@echo "$(MY_NAME_IS) export VAULT_ADDR for the active node: export VAULT_ADDR=https://127.0.0.1:8200"
	@echo "$(MY_NAME_IS) login to Vault with initial root token: vault login $$(grep 'Initial Root Token' $(VDL_INIT) | awk '{print $$NF}')"

done-stage:
	@echo "$(MY_NAME_IS) export VAULT_ADDR for the active node: export VAULT_ADDR=https://127.0.0.1:8200"
	@echo "$(MY_NAME_IS) Vault is not initialized or unsealed. You must initialize and unseal Vault before use."

DOCKER_OK=$$(docker info > /dev/null 2>&1; printf $$?)
TERRAFORM_BINARY_OK=$$(which terraform > /dev/null 2>&1 ; printf $$?)
VAULT_BINARY_OK=$$(which vault > /dev/null 2>&1 ; printf $$?)
prerequisites:
	@if [ $(VAULT_BINARY_OK) -ne 0 ] ; then echo "$(MY_NAME_IS) Vault binary not found in path!"; echo "$(MY_NAME_IS) install Vault and try again: https://developer.hashicorp.com/vault/downloads." ; exit 1 ; fi
	@if [ $(TERRAFORM_BINARY_OK) -ne 0 ] ; then echo "$(MY_NAME_IS) Terraform CLI binary not found in path!" ; echo "$(MY_NAME_IS) install Terraform CLI and try again: https://developer.hashicorp.com/terraform/downloads" ; exit 1 ; fi
	@if [ $(DOCKER_OK) -ne 0 ] ; then echo "$(MY_NAME_IS) can't get Docker info; ensure that Docker is running, and try again." ; exit 1 ; fi

provision:
	@if [ "$(UNAME)" = "Linux" ]; then echo "$(MY_NAME_IS) [Linux] Setting ownership on container volume directories ..."; echo "$(MY_NAME_IS) [Linux] You could be prompted for your user password by sudo."; sudo chown -R $$USER:$$USER containers; sudo chmod -R 0777 containers; fi
	@printf "$(MY_NAME_IS) initializing Terraform workspace ..."
	@terraform init > $(VDL_LOG_FILE)
	@echo 'done.'
	@printf "$(MY_NAME_IS) applying Terraform configuration ..."
	@terraform apply -auto-approve >> $(VDL_LOG_FILE)
	@echo 'done.'

UNSEAL_KEY=$$(grep 'Unseal Key 1' $(VDL_INIT) | awk '{print $$NF}')
unseal_nodes:
	@printf "$(MY_NAME_IS) unsealing cluster nodes ..."
	@until [ $$(VAULT_ADDR=https://127.0.0.1:8220 vault status | grep "Initialized" | awk '{print $$2}') = "true" ] ; do sleep 1 ; printf . ; done
	@VAULT_ADDR=https://127.0.0.1:8220 vault operator unseal $(UNSEAL_KEY) >> $(VDL_LOG_FILE)
	@printf 'node 2. '
	@until [ $$(VAULT_ADDR=https://127.0.0.1:8230 vault status | grep "Initialized" | awk '{print $$2}') = "true" ] ; do sleep 1 ; printf . ; done
	@VAULT_ADDR=https://127.0.0.1:8230 vault operator unseal $(UNSEAL_KEY) >> $(VDL_LOG_FILE)
	@printf 'node 3. '
	@until [ $$(VAULT_ADDR=https://127.0.0.1:8240 vault status | grep "Initialized" | awk '{print $$2}') = "true" ] ; do sleep 1 ; printf . ; done
	@VAULT_ADDR=https://127.0.0.1:8240 vault operator unseal $(UNSEAL_KEY) >> $(VDL_LOG_FILE)
	@printf 'node 4. '
	@until [ $$(VAULT_ADDR=https://127.0.0.1:8250 vault status | grep "Initialized" | awk '{print $$2}') = "true" ] ; do sleep 1 ; printf . ; done
	@VAULT_ADDR=https://127.0.0.1:8250 vault operator unseal $(UNSEAL_KEY) >> $(VDL_LOG_FILE)
	@printf 'node 5. '
	@echo 'done.'

ROOT_TOKEN=$$(grep 'Initial Root Token' $(VDL_INIT) | awk '{print $$NF}')
audit_device:
	@printf "$(MY_NAME_IS) enable audit device ..."
	@VAULT_ADDR=https://127.0.0.1:8200 VAULT_TOKEN=$(ROOT_TOKEN) vault audit enable file file_path=/vault/logs/vault_audit.log > /dev/null 2>&1
	@echo 'done.'

vault_status:
	@printf "$(MY_NAME_IS) check Vault active node status ..."
	@until [ $$(VAULT_ADDR=https://127.0.0.1:8200 vault status > /dev/null 2>&1 ; printf $$?) -eq 0 ] ; do sleep 1 && printf . ; done
	@echo 'done.'
	@printf "$(MY_NAME_IS) check Vault initialization status ..."
	@until [ $$(VAULT_ADDR=https://127.0.0.1:8200 vault status | grep "Initialized" | awk '{print $$2}') = "true" ] ; do sleep 1 ; printf . ; done
	@echo 'done.'

clean:
	@if [ "$(UNAME)" = "Linux" ]; then echo "$(MY_NAME_IS) [Linux] setting ownership on container volume directories ..."; echo "$(MY_NAME_IS) [Linux] You could be prompted for your user password by sudo."; sudo chown -R $$USER:$$USER containers; fi
	@printf "$(MY_NAME_IS) destroying Terraform configuration ..."
	@terraform destroy -auto-approve >> $(VDL_LOG_FILE)
	@echo 'done.'
	@printf "$(MY_NAME_IS) Removing artifacts created by $(MY_NAME_IS) ..."
	@rm -rf $(VDL_DATA)
	@rm -f $(VAULT_DOCKER_LAB_INIT)
	@rm -rf $(VDL_AUDIT_LOGS)
	@rm -f $(VDL_LOG_FILE)
	@echo 'done.'

cleanest: clean
	@printf "$(MY_NAME_IS) Removing all Terraform runtime configuration and state ..."
	@rm -f terraform.tfstate
	@rm -f terraform.tfstate.backup
	@rm -rf .terraform
	@rm -f .terraform.lock.hcl
	@echo 'done.'

.PHONY: all
