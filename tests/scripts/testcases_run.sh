#!/bin/bash
set -euxo pipefail

export PYPATH=$([[ ! "$CI_JOB_NAME" =~ "coreos" ]] && echo /usr/bin/python || echo /opt/bin/python)
echo "CI_JOB_NAME is $CI_JOB_NAME"
echo "PYPATH is $PYPATH"
pwd
ls
echo ${PWD}
cd tests && make create-${CI_PLATFORM} -s ; cd -

# Check out latest tag if testing upgrade
test "${UPGRADE_TEST}" != "false" && git fetch --all && git checkout $(git describe --tags $(git rev-list --tags --max-count=1))
# Checkout the CI vars file so it is available
test "${UPGRADE_TEST}" != "false" && git checkout "${CI_BUILD_REF}" tests/files/${CI_JOB_NAME}.yml

# Create cluster
ansible-playbook -i ${ANSIBLE_INVENTORY} -b --become-user=root --private-key=${HOME}/.ssh/id_rsa -u $SSH_USER ${LOG_LEVEL} -e @${CI_TEST_VARS} -e ansible_ssh_user=${SSH_USER} -e local_release_dir=${PWD}/downloads --limit "all:!fake_hosts" cluster.yml

# Repeat deployment if testing upgrade
if [ "${UPGRADE_TEST}" != "false" ]; then
  test "${UPGRADE_TEST}" == "basic" && PLAYBOOK="cluster.yml"
  test "${UPGRADE_TEST}" == "graceful" && PLAYBOOK="upgrade-cluster.yml"
  git checkout "${CI_BUILD_REF}"
  ansible-playbook -i ${ANSIBLE_INVENTORY} -b --become-user=root --private-key=${HOME}/.ssh/id_rsa -u $SSH_USER ${LOG_LEVEL} -e @${CI_TEST_VARS} -e ansible_ssh_user=${SSH_USER} -e local_release_dir=${PWD}/downloads --limit "all:!fake_hosts" $PLAYBOOK
fi

# Tests Cases
## Test Master API
ansible-playbook -i ${ANSIBLE_INVENTORY} -e ansible_python_interpreter=${PYPATH} -u $SSH_USER -e ansible_ssh_user=$SSH_USER -b --become-user=root --limit "all:!fake_hosts" tests/testcases/010_check-apiserver.yml $LOG_LEVEL

## Test that all pods are Running
ansible-playbook -i ${ANSIBLE_INVENTORY} -e ansible_python_interpreter=${PYPATH} -u $SSH_USER -e ansible_ssh_user=$SSH_USER -b --become-user=root --limit "all:!fake_hosts" tests/testcases/015_check-pods-running.yml $LOG_LEVEL

## Test pod creation and ping between them
ansible-playbook -i ${ANSIBLE_INVENTORY} -e ansible_python_interpreter=${PYPATH} -u $SSH_USER -e ansible_ssh_user=$SSH_USER -b --become-user=root --limit "all:!fake_hosts" tests/testcases/030_check-network.yml $LOG_LEVEL

## Advanced DNS checks
ansible-playbook -i ${ANSIBLE_INVENTORY} -e ansible_python_interpreter=${PYPATH} -u $SSH_USER -e ansible_ssh_user=$SSH_USER -b --become-user=root --limit "all:!fake_hosts" tests/testcases/040_check-network-adv.yml $LOG_LEVEL

## Idempotency checks 1/5 (repeat deployment)
if [ "${IDEMPOT_CHECK}" = "true" ]; then
  ansible-playbook -i ${ANSIBLE_INVENTORY} -b --become-user=root --private-key=${HOME}/.ssh/id_rsa -u $SSH_USER ${LOG_LEVEL} -e @${CI_TEST_VARS} -e ansible_python_interpreter=${PYPATH} -e local_release_dir=${PWD}/downloads --limit "all:!fake_hosts" cluster.yml
fi

## Idempotency checks 2/5 (Advanced DNS checks)
if [ "${IDEMPOT_CHECK}" = "true" ]; then
  ansible-playbook -i ${ANSIBLE_INVENTORY} -b --become-user=root --private-key=${HOME}/.ssh/id_rsa -u $SSH_USER ${LOG_LEVEL} -e @${CI_TEST_VARS} --limit "all:!fake_hosts" tests/testcases/040_check-network-adv.yml
fi

## Idempotency checks 3/5 (reset deployment)
if [ "${IDEMPOT_CHECK}" = "true" -a "${RESET_CHECK}" = "true" ]; then
  ansible-playbook -i ${ANSIBLE_INVENTORY} -b --become-user=root --private-key=${HOME}/.ssh/id_rsa -u $SSH_USER ${LOG_LEVEL} -e @${CI_TEST_VARS} -e ansible_python_interpreter=${PYPATH} -e reset_confirmation=yes --limit "all:!fake_hosts" reset.yml
fi

## Idempotency checks 4/5 (redeploy after reset)
if [ "${IDEMPOT_CHECK}" = "true" -a "${RESET_CHECK}" = "true" ]; then
  ansible-playbook -i ${ANSIBLE_INVENTORY} -b --become-user=root --private-key=${HOME}/.ssh/id_rsa -u $SSH_USER ${LOG_LEVEL} -e @${CI_TEST_VARS} -e ansible_python_interpreter=${PYPATH} -e local_release_dir=${PWD}/downloads --limit "all:!fake_hosts" cluster.yml
fi

## Idempotency checks 5/5 (Advanced DNS checks)
if [ "${IDEMPOT_CHECK}" = "true" -a "${RESET_CHECK}" = "true" ]; then
  ansible-playbook -i ${ANSIBLE_INVENTORY} -e ansible_python_interpreter=${PYPATH} -u $SSH_USER -e ansible_ssh_user=$SSH_USER -b --become-user=root --limit "all:!fake_hosts" tests/testcases/040_check-network-adv.yml $LOG_LEVEL
fi
