#!/bin/bash

NEO4J_HOSTNAME='http://dist.neo4j.org'
DEFAULT_VERSION='all'
LAST_VERSION='2.3.1'

# ==============================================================================
# PROVISION
# ==============================================================================

versions=()
tests=()

while getopts ":v:" optname
do
  case "${optname}" in
    v)
      versions+=( ${OPTARG} )
      ;;
    *)
      echo "Invalid parameters"
      exit 1
      ;;
  esac
done

test_name=${@:$OPTIND:1}

# If there are not any argument specified then test just with default Neo4j
# version
if [ ${#versions[@]} -eq 0 ]; then
  versions=("$DEFAULT_VERSION")

fi

# If is all then test with all Neo4j versions
if [ ${versions[0]} = 'all' ]; then
  versions=(1.8.3 1.9.9 2.0.5 2.1.8 2.2.7 2.3.1)
fi

# On fake_neo4j_host is used to save cache tars
mkdir -p fake_neo4j_host

# If some Neo4J version has not been downloaded then try to download it, so can
# test locally reducing remote http requests.
for version in "${versions[@]}"; do
  tar_name="neo4j-community-$version-unix.tar.gz"
  if [ ! -f fake_neo4j_host/${tar_name} ]; then
    printf "\n\nDownloading ${version}\n\n"
    if ! curl -f -o /tmp/${$}.${tar_name} ${NEO4J_HOSTNAME}/${tar_name}; then
      printf "\n\nError downloading ${version}\nThe test has been aborted!!!\n"
      exit 0
    fi

    mv /tmp/${$}.${tar_name} fake_neo4j_host/${tar_name}
  fi
done

# fake_ineo_host is used to make a fake update on tests, this will be the last
# ineo script but with a different version
mkdir -p fake_ineo_host

cp ./ineo ./fake_ineo_host/ineo
sed -i.bak "/^\(VERSION=\).*/s//\1x.x.x/" ./fake_ineo_host/ineo

set -e

# Load assert.sh library (More info: http://github.com/lehmannro/assert.sh)
. assert.sh

# ==============================================================================
# PID FUNCTIONS
# ==============================================================================

function set_instance_pid {
  local instance_name=$1
  assert_raises \
    "test -f $INEO_HOME/instances/$instance_name/data/neo4j-service.pid" 0
  pid=$(head -n 1 $INEO_HOME/instances/$instance_name/data/neo4j-service.pid)
}

function assert_run_pid {
  local pid=$1
  assert_raises "test $(ps -p $pid -o pid=)" 0
}

function assert_not_run_pid {
  local pid=$1
  assert_raises "test $(ps -p $pid -o pid=)" 1
}

# ==============================================================================
# RESET FUNCTION
# ==============================================================================

function setup {
  rm -fr ineo_for_test
  assert_raises "test -d ineo_for_test" 1
}

# ==============================================================================
# TEST INSTALL
# ==============================================================================

InstallWithIncorrectParameters() {
  setup

  local params=(
    "-e $(pwd)/ineo_for_test" 'e'
    "-e$(pwd)/ineo_for_test" 'e'
    "x -d $(pwd)/ineo_for_test" 'x'
    "x -d$(pwd)/ineo_for_test" 'x'
    "-d $(pwd)/ineo_for_test y" 'y'
    "-d$(pwd)/ineo_for_test y" 'y'
  )

  local i
  for ((i=0; i<${#params[*]}; i+=2)); do
    assert_raises "./ineo install ${params[i]}" 1
    assert        "./ineo install ${params[i]}" \
"
  ERROR: Invalid argument or option: ${params[i+1]}!

  For help about the command 'install' type:
  ineo help install
"
  done

  assert_end InstallWithIncorrectParameters
}
tests+=('InstallWithIncorrectParameters')


InstallWithARelativePath() {
  setup

  local params=(
    '-d ineo_for_test'
    '-dineo_for_test'
  )

  for param in "${params[@]}"; do
    assert_raises "./ineo install $param" 1
    assert        "./ineo install $param" \
"
  ERROR: The directory 'ineo_for_test' is not an absolute path!

  Use directories like:
  /opt/ineo
  ~/.ineo
"
  done

  assert_end InstallWithARelativePath
}
tests+=('InstallWithARelativePath')


InstallOnAnExistingDirectory() {
  setup

  assert_raises "mkdir $(pwd)/ineo_for_test" 0

  local params=(
    "-d $(pwd)/ineo_for_test"
    "-d$(pwd)/ineo_for_test"
  )

  local param
  for param in "${params[@]}"; do
    assert_raises "./ineo install $param" 1
    assert        "./ineo install $param" \
"
  ERROR: The directory '$(pwd)/ineo_for_test' already exists!

  If you want reinstall ineo then uninstall it with:
  ineo uninstall -d $(pwd)/ineo_for_test

  or ensure the directory doesn't contain anything important then remove it with:
  rm -r $(pwd)/ineo_for_test
"
  done

  assert_end InstallOnAnExistingDirectory
}
tests+=('InstallOnAnExistingDirectory')


InstallCorrectly() {
  local params=(
    "-d $(pwd)/ineo_for_test"
    "-d$(pwd)/ineo_for_test"
  )

  for param in "${params[@]}"; do
    setup

    assert "./ineo install $param" \
"
  Ineo was successfully installed in $(pwd)/ineo_for_test.

  To start using the 'ineo' command reopen your terminal or enter:
  source ~/.bash_profile
"

    assert_raises "test -d ineo_for_test" 0
    assert_raises "test -d ineo_for_test/bin" 0
    assert_raises "test -d ineo_for_test/instances" 0
    assert_raises "test -d ineo_for_test/cache" 0

    assert_raises \
      "grep -Fq 'export INEO_HOME=$(pwd)/ineo_for_test; export PATH=\$INEO_HOME/bin:\$PATH' ~/.bash_profile" 0
  done

  assert_end InstallCorrectly
}
tests+=('InstallCorrectly')

# ==============================================================================
# TEST UNINSTALL
# ==============================================================================

UninstallWithIncorrectParameters() {
  setup

  local params=(
    "-e $(pwd)/ineo_for_test" 'e'
    "-e$(pwd)/ineo_for_test" 'e'
    "x -d $(pwd)/ineo_for_test" 'x'
    "x -d$(pwd)/ineo_for_test" 'x'
    "-d $(pwd)/ineo_for_test y" 'y'
    "-d$(pwd)/ineo_for_test y" 'y'
    "-e $(pwd)/ineo_for_test -f" 'e'
    "-e$(pwd)/ineo_for_test -f" 'e'
    "x -d $(pwd)/ineo_for_test -f" 'x'
    "x -d$(pwd)/ineo_for_test -f" 'x'
    "-f -d $(pwd)/ineo_for_test y" 'y'
    "-f -d$(pwd)/ineo_for_test y" 'y'
  )

  local i
  for ((i=0; i<${#params[*]}; i+=2)); do
    assert_raises "./ineo uninstall ${params[i]}" 1
    assert        "./ineo uninstall ${params[i]}" \
"
  ERROR: Invalid argument or option: ${params[i+1]}!

  For help about the command 'uninstall' type:
  ineo help uninstall
"
  done

  assert_end UninstallWithIncorrectParameters
}
tests+=('UninstallWithIncorrectParameters')


UninstallWithARelativeDirectory() {
  setup

  local params=(
    '-d ineo_for_test'
    '-dineo_for_test'
  )

  local param
  for param in "${params[@]}"; do
    assert_raises "./ineo uninstall $param" 1
    assert        "./ineo uninstall $param" \
"
  ERROR: The directory 'ineo_for_test' is not an absolute path!

  Use directories like:
  /opt/ineo
  ~/.ineo
"
  done

  assert_end UninstallWithARelativeDirectory
}
tests+=('UninstallWithARelativeDirectory')


UninstallWithANonExistentDirectory() {
  setup

  local params=(
    "-d $(pwd)/ineo_for_test"
    "-d$(pwd)/ineo_for_test"
  )

  # Ensure that directory doesn't exists
  assert_raises "test -d $(pwd)/ineo_for_test" 1

  local param
  for param in "${params[@]}"; do
    assert_raises "./ineo uninstall $param" 1
    assert        "./ineo uninstall $param" \
"
  ERROR: The directory '$(pwd)/ineo_for_test' doesn't exists!

  Are you sure Ineo is installed?
"
  done

  assert_end UninstallWithANonExistentDirectory
}
tests+=('UninstallWithANonExistentDirectory')


UninstallWithADirectoryThatDoesntLookLikeAnIneoDirectory() {
  setup

  local params=(
    "-d $(pwd)/ineo_for_test"
    "-d$(pwd)/ineo_for_test"
  )

  local param
  for param in "${params[@]}"; do

    # Make an installation
    assert_raises "./ineo install -d $(pwd)/ineo_for_test" 0

    # Remove a directory from Ineo
    assert_raises "rm -fr $(pwd)/ineo_for_test/neo4j" 0

    # Try uninstall saying no to first prompt
    assert "echo -ne 'n\n' | ./ineo uninstall $param" \
"
  WARNING: The directory '$(pwd)/ineo_for_test' doesn't look like an Ineo directory!
"
    # Ensure that directory exists yet
    assert_raises "test -d $(pwd)/ineo_for_test" 0


    # Try uninstall saying yes to first prompt and no to second prompt
    assert "echo -ne 'y\nn\n' | ./ineo uninstall $param" \
"
  WARNING: The directory '$(pwd)/ineo_for_test' doesn't look like an Ineo directory!


  WARNING: This action will remove everything in '$(pwd)/ineo_for_test'!
"
    # Ensure that directory exists yet
    assert_raises "test -d $(pwd)/ineo_for_test" 0


    # Uninstall saying yes to first prompt and yes to second prompt
    assert "echo -ne 'y\ny\n' | ./ineo uninstall $param" \
"
  WARNING: The directory '$(pwd)/ineo_for_test' doesn't look like an Ineo directory!


  WARNING: This action will remove everything in '$(pwd)/ineo_for_test'!


  Ineo was successfully uninstalled
"
    # Ensure that directory doesn't exists
    assert_raises "test -d $(pwd)/ineo_for_test" 1
  done

  assert_end UninstallWithADirectoryThatDoesntLookLikeAnIneoDirectory
}
tests+=('UninstallWithADirectoryThatDoesntLookLikeAnIneoDirectory')


UninstallWithADirectoryThatDoesntLookLikeAnIneoDirectoryUsingF() {
  setup

  local params=(
    "-d $(pwd)/ineo_for_test -f"
    "-d$(pwd)/ineo_for_test -f"
    "-f -d $(pwd)/ineo_for_test"
    "-f -d$(pwd)/ineo_for_test"
  )

  local param
  for param in "${params[@]}"; do
    # Make an installation
    assert_raises "./ineo install -d $(pwd)/ineo_for_test" 0

    # Remove a directory from Ineo
    assert_raises "rm -fr $(pwd)/ineo_for_test/neo4j" 0

    # Ensure that directory exists yet
    assert_raises "test $(pwd)/ineo_for_test" 0

    # Uninstall using force
    assert "./ineo uninstall $param" \
"
  Ineo was successfully uninstalled
"

    # Ensure that directory doesn't exists
    assert_raises "test -d $(pwd)/ineo_for_test" 1
  done

  assert_end UninstallWithADirectoryThatDoesntLookLikeAnIneoDirectoryUsingF
}
tests+=('UninstallWithADirectoryThatDoesntLookLikeAnIneoDirectoryUsingF')


# ==============================================================================
# TEST CREATE
# ==============================================================================

CreateAnInstanceWithoutTheRequiredParameter() {
  setup

  # Make an installation
  assert_raises "./ineo install -d $(pwd)/ineo_for_test" 0

  assert_raises "./ineo create" 1
  assert "./ineo create" \
"
  ERROR: create requires an instance name!

  For help about the command 'create' type:
  ineo help create
"

  assert_end CreateAnInstanceWithoutTheRequiredParameter
}
tests+=('CreateAnInstanceWithoutTheRequiredParameter')

CreateWithIncorrectParameters() {
  setup

  local params=(
    "-x" 'x'
    "-d -x" 'x'
    "-f -x" 'x'
    "-p7474 -x" 'x'
    "-s7878 -x" 'x'
    "-v$DEFAULT_VERSION -x" 'x'
    "-p7474 -s7878 -v$DEFAULT_VERSION -d -f -x" 'x'
    "facebook twitter" 'twitter'
    "-x facebook twitter" 'x'
    "-p7474 facebook twitter" 'twitter'
    "-p7474 -s7878 -v$DEFAULT_VERSION -d -f facebook twitter" 'twitter'
  )

  local i
  for ((i=0; i<${#params[*]}; i+=2)); do
    assert_raises "./ineo create ${params[i]}" 1
    assert        "./ineo create ${params[i]}" \
"
  ERROR: Invalid argument or option: ${params[i+1]}!

  For help about the command 'create' type:
  ineo help create
"
  done

  assert_end CreateWithIncorrectParameters
}
tests+=('CreateWithIncorrectParameters')

# Set the variables to create instances
# ------------------------------------------------------------------------------

export NEO4J_HOSTNAME="file:///$(pwd)/fake_neo4j_host"
export INEO_HOSTNAME="file:///$(pwd)/fake_ineo_host"
export INEO_HOME="$(pwd)/ineo_for_test"

CreateAnInstanceCorrectlyWithDifferentVariationsOfParameters() {
  # The parameters to check are 'port' 'ssl port' 'version'
  local params=(
    'twitter'                        '7474' '7475' "$LAST_VERSION"
    '-p8484 twitter'                 '8484' '8485' "$LAST_VERSION"
    '-s9495 twitter'                 '7474' '9495' "$LAST_VERSION"
    '-p8484 -s9495 twitter'          '8484' '9495' "$LAST_VERSION"
    '-v1.9.9 twitter'                '7474' '7475' '1.9.9'
    '-p8484 -v1.9.9 twitter'         '8484' '8485' '1.9.9'
    '-s9495 -v1.9.9 twitter'         '7474' '9495' '1.9.9'
    '-p8484 -s9495 -v1.9.9 twitter'  '8484' '9495' '1.9.9'
  )

  local i
  for ((i=0; i<${#params[*]}; i+=4)); do
    setup

    local port=${params[i+1]}
    local ssl_port=${params[i+2]}
    local version=${params[i+3]}
    local config="$(pwd)/ineo_for_test/instances/twitter/conf/neo4j-server.properties"

    # Make an installation
    assert_raises "./ineo install -d $(pwd)/ineo_for_test" 0

    # Create the instance
    assert "./ineo create ${params[i]}" \
"
  The instance twitter was created successfully

"
    # Ensure the correct neo4j version was downloaded
    assert_raises \
      "test -f $(pwd)/ineo_for_test/neo4j/neo4j-community-$version-unix.tar.gz" 0

    # Ensure neo4j exists
    assert_raises "test -f $(pwd)/ineo_for_test/instances/twitter/bin/neo4j" 0

    # Ensure the correct ports were set
    assert_raises "grep -Fq org\.neo4j\.server\.webserver\.port=$port $config" 0
    assert_raises \
      "grep -Fq org\.neo4j\.server\.webserver\.https\.port=$ssl_port $config" 0

  done

  assert_end CreateAnInstanceCorrectlyWithDifferentVariationsOfParameters
}
tests+=('CreateAnInstanceCorrectlyWithDifferentVariationsOfParameters')


CreateAnInstanceCorrectlyWithEveryVersion() {

  local version
  for version in "${versions[@]}"; do
    setup

    local config="$(pwd)/ineo_for_test/instances/twitter/conf/neo4j-server.properties"

    # Make an installation
    assert_raises "./ineo install -d $(pwd)/ineo_for_test" 0

    # Create the instance
    assert "./ineo create -p8484 -s9495 -v $version twitter" \
"
  The instance twitter was created successfully

"
    # Ensure the correct neo4j version was downloaded
    assert_raises \
      "test -f $(pwd)/ineo_for_test/neo4j/neo4j-community-$version-unix.tar.gz" 0

    # Ensure neo4j exists
    assert_raises "test -f $(pwd)/ineo_for_test/instances/twitter/bin/neo4j" 0

    # Ensure the correct ports were set
    assert_raises "grep -Fq org\.neo4j\.server\.webserver\.port=$port $config" 0
    assert_raises \
      "grep -Fq org\.neo4j\.server\.webserver\.https\.port=$ssl_port $config" 0

  done

  assert_end CreateAnInstanceCorrectlyWithEveryVersion
}
tests+=('CreateAnInstanceCorrectlyWithEveryVersion')


CreateAnInstanceWithABadTarAndTryAgainWithDOption() {
  setup

  # Truncate a bad version, so is possible a bad tar
  rm -fr bad_tar_for_test
  mkdir bad_tar_for_test

  cp fake_neo4j_host/neo4j-community-${LAST_VERSION}-unix.tar.gz bad_tar_for_test

  local platform=$(uname -s | tr '[:upper:]' '[:lower:]')

  local command_truncate
  if [ $platform = 'darwin' ]; then
    command_truncate=gtruncate
  elif [ $platform = 'linux' ]; then
    command_truncate=truncate
  fi

  $command_truncate -s20MB bad_tar_for_test/neo4j-community-${LAST_VERSION}-unix.tar.gz

  # Change the NEO4J_HOSTNAME for test to download the bad tar
  export NEO4J_HOSTNAME="file:///$(pwd)/bad_tar_for_test"

  # Make an installation
  assert_raises "./ineo install -d $(pwd)/ineo_for_test" 0

  # Create the instance with a bad tar version
  assert "./ineo create -v$LAST_VERSION twitter" \
"
  ERROR: The tar file 'neo4j-community-$LAST_VERSION-unix.tar.gz' can't be extracted!

  Try run the command 'create' with the -d option to download the tar file again

"
  # Ensure the bad tar version of neo4j was downloaded
  assert_raises \
    "test -f $(pwd)/ineo_for_test/neo4j/neo4j-community-$LAST_VERSION-unix.tar.gz" 0

  # Ensure the instance doesn't exists
  assert_raises "test -d $(pwd)/ineo_for_test/instances/twitter" 1

  # The bad tar now must be good
  rm -fr bad_tar_for_test
  mkdir bad_tar_for_test

  cp fake_neo4j_host/neo4j-community-${LAST_VERSION}-unix.tar.gz bad_tar_for_test

  # Create the instance with a good tar version
  assert "./ineo create -d -v$LAST_VERSION twitter" \
"
  The instance twitter was created successfully

"
  # Ensure the correct neo4j version was downloaded
  assert_raises \
    "test -f $(pwd)/ineo_for_test/neo4j/neo4j-community-$LAST_VERSION-unix.tar.gz" 0

  # Ensure neo4j exists
  assert_raises "test -f $(pwd)/ineo_for_test/instances/twitter/bin/neo4j" 0

  # Restore the correct NEO4J_HOSTNAME for test
  export NEO4J_HOSTNAME="file:///$(pwd)/fake_neo4j_host"

  assert_end CreateAnInstanceWithABadTarAndTryAgainWithDOption
}
tests+=('CreateAnInstanceWithABadTarAndTryAgainWithDOption')


CreateAnInstanceOnAExistingDirectoryAndTryAgainWithFOption() {
  setup

  # Make an installation
  assert_raises "./ineo install -d $(pwd)/ineo_for_test" 0

  # Create the intance directory by hand
  assert_raises "mkdir $(pwd)/ineo_for_test/instances/twitter"

  # Try create the instance
  assert "./ineo create twitter" \
"
  ERROR: A directory for the instance 'twitter' already exists!

  Maybe the instance already was created or try run the command 'install' with the -f option to force the installation

"

  # Ensure the bad tar version of neo4j was downloaded
  assert_raises \
    "test -f $(pwd)/ineo_for_test/neo4j/neo4j-community-$LAST_VERSION-unix.tar.gz" 0

  # Ensure the instance directory is empty yet
  assert_raises "test $(ls -A ineo_for_test/instances/twitter)" 1

  # Create the instance with -f option
  assert "./ineo create -f twitter" \
"
  The instance twitter was created successfully

"

  # Ensure neo4j exists
  assert_raises "test -f $(pwd)/ineo_for_test/instances/twitter/bin/neo4j" 0

  assert_end CreateAnInstanceOnAExistingDirectoryAndTryAgainWithFOption
}
tests+=('CreateAnInstanceOnAExistingDirectoryAndTryAgainWithFOption')


CreateAnInstanceWithoutTheRequiredParameter() {
  setup

  # Make an installation
  assert_raises "./ineo install -d $(pwd)/ineo_for_test" 0

  assert_raises "./ineo create" 1
  assert "./ineo create" \
"
  ERROR: create requires an instance name!

  For help about the command 'create' type:
  ineo help create
"

  assert_end CreateAnInstanceWithoutTheRequiredParameter
}
tests+=('CreateAnInstanceWithoutTheRequiredParameter')


# ==============================================================================
# TEST INSTANCE ACTIONS (START, STATUS, RESTART, STOP)
# ==============================================================================

actions=('start' 'status' 'restart' 'stop')

ActionsWithIncorrectParameters() {
  setup

  local params=(
    "-x" 'x'
    "-x -y" 'x'
    "-x twitter" 'x'
    "facebook twitter" 'twitter'
    "-x facebook twitter" 'x'
  )

  local i j
  for ((i=0; i<${#actions[*]}; i+=1)); do
    for ((j=0; j<${#params[*]}; j+=2)); do
      assert_raises "./ineo ${actions[i]} ${params[j]}" 1
      assert        "./ineo ${actions[i]} ${params[j]}" \
"
  ERROR: Invalid argument or option: ${params[j+1]}!

  For help about the command '${actions[i]}' type:
  ineo help ${actions[i]}
"
    done
  done

  assert_end ActionsWithIncorrectParameters
}
tests+=('ActionsWithIncorrectParameters')


ActionsOnANonExistentInstance() {
  setup

  # Make an installation
  assert_raises "./ineo install -d $(pwd)/ineo_for_test" 0

  local action
  for action in "${actions[@]}"; do
    assert_raises "./ineo $action twitter" 1
    assert        "./ineo $action twitter" \
"
  ERROR: There is not an instance with the name 'twitter'!

  You can create an instance with the command 'ineo create twitter'
"
  done

  assert_end ActionsOnANonExistentInstance
}
tests+=('ActionsOnANonExistentInstance')


ActionsOnANotProperlyInstalledInstance() {
  setup

  # Make an installation
  assert_raises "./ineo install -d $(pwd)/ineo_for_test" 0

  mkdir ineo_for_test/instances/twitter

  local action
  for action in "${actions[@]}"; do
    assert_raises "./ineo $action twitter" 1
    assert        "./ineo $action twitter" \
"
  ERROR: The instance 'twitter' seems that is not properly installed!

  You can recreate the instance with the command 'ineo create -f twitter'
"
  done

  assert_end ActionsOnANotProperlyInstalledInstance
}
tests+=('ActionsOnANotProperlyInstalledInstance')


ExecuteActionsCorrectly() {
  local version
  for version in "${versions[@]}"; do
    setup

    # Make an installation
    assert_raises "./ineo install -d $(pwd)/ineo_for_test" 0

    assert_raises "./ineo create -v $version twitter" 0

    # start
    assert_raises "./ineo start twitter" 0
    set_instance_pid twitter
    assert_run_pid $pid

    # status running
    assert "./ineo status twitter" \
"
  status 'twitter'
  Neo4j Server is running at pid $pid
"

    # restart
    assert_raises "./ineo restart twitter" 0
    set_instance_pid twitter
    assert_run_pid $pid

    # status running
    assert "./ineo status twitter" \
"
  status 'twitter'
  Neo4j Server is running at pid $pid
"

    # stop
    assert_raises "./ineo stop twitter" 0
    assert_not_run_pid $pid

    # status not running
    assert "./ineo status twitter" \
"
  status 'twitter'
  Neo4j Server is not running
"
  done
  assert_end ExecuteActionsCorrectly
}
tests+=('ExecuteActionsCorrectly')


ExecuteActionsOnVariousInstancesCorrectly() {
  local version
  for version in "${versions[@]}"; do
    setup

    # Make an installation
    assert_raises "./ineo install -d $(pwd)/ineo_for_test" 0

    # Test confirming
    assert_raises "./ineo create -p7474 -v $version twitter" 0
    assert_raises "./ineo create -p7476 -v $version facebook" 0

    # start
    assert_raises "echo -ne 'y\n' | ./ineo start" 0

    set_instance_pid twitter
    local pid_twitter=$pid
    assert_run_pid $pid_twitter

    set_instance_pid facebook
    local pid_facebook=$pid
    assert_run_pid $pid_facebook

    # status running
    assert "./ineo status" \
"
  status 'facebook'
  Neo4j Server is running at pid $pid_facebook

  status 'twitter'
  Neo4j Server is running at pid $pid_twitter
"

    # restart
    assert_raises "echo -ne 'y\n' | ./ineo restart" 0

    set_instance_pid twitter
    pid_twitter=$pid
    assert_run_pid $pid_twitter

    set_instance_pid facebook
    pid_facebook=$pid
    assert_run_pid $pid_facebook

    # status running
    assert "./ineo status" \
"
  status 'facebook'
  Neo4j Server is running at pid $pid_facebook

  status 'twitter'
  Neo4j Server is running at pid $pid_twitter
"

    # stop
    assert_raises "echo -ne 'y\n' | ./ineo stop" 0
    assert_not_run_pid $pid_twitter
    assert_not_run_pid $pid_facebook

    # status not running
    assert "./ineo status" \
"
  status 'facebook'
  Neo4j Server is not running

  status 'twitter'
  Neo4j Server is not running
"

    # Test forcing with -q

    # start
    assert_raises "./ineo start -q" 0

    set_instance_pid twitter
    pid_twitter=$pid
    assert_run_pid $pid_twitter

    set_instance_pid facebook
    pid_facebook=$pid
    assert_run_pid $pid_facebook

    # status running
    assert "./ineo status" \
"
  status 'facebook'
  Neo4j Server is running at pid $pid_facebook

  status 'twitter'
  Neo4j Server is running at pid $pid_twitter
"

    # restart
    assert_raises "./ineo restart -q" 0

    set_instance_pid twitter
    pid_twitter=$pid
    assert_run_pid $pid_twitter

    set_instance_pid facebook
    pid_facebook=$pid
    assert_run_pid $pid_facebook

    # status running
    assert "./ineo status" \
"
  status 'facebook'
  Neo4j Server is running at pid $pid_facebook

  status 'twitter'
  Neo4j Server is running at pid $pid_twitter
"

    assert_raises "./ineo stop -q" 0
    assert_not_run_pid $pid_twitter
    assert_not_run_pid $pid_facebook

    # status not running
    assert "./ineo status" \
"
  status 'facebook'
  Neo4j Server is not running

  status 'twitter'
  Neo4j Server is not running
"
  done
  assert_end ExecuteActionsOnVariousInstancesCorrectly
}
tests+=('ExecuteActionsOnVariousInstancesCorrectly')


# ==============================================================================
# TEST INSTANCES
# ==============================================================================

InstancesWithIncorrectParameters() {
  setup

  params=(
    'wrong'
    '-q'
  )

  local param
  for param in "${params[@]}"; do
    assert_raises "./ineo instances $param" 1
    assert        "./ineo instances $param" \
"
  ERROR: Invalid argument or option: $param!

  For help about the command 'instances' type:
  ineo help instances
"
  done

  assert_end InstancesWithIncorrectParameters
}
tests+=('InstancesWithIncorrectParameters')


InstancesCorrectly() {
  for version in "${versions[@]}"; do
    setup

    # Make an installation
    assert_raises "./ineo install -d $(pwd)/ineo_for_test" 0

    assert_raises "./ineo create -p7474 -s8484 -v $version twitter" 0
    assert_raises "./ineo create -p7575 -s8585 -v $version facebook" 0

    assert_raises "./ineo instances" 0
    assert        "./ineo instances" \
"
  > instance 'facebook'
    VERSION: $version
    PATH:    $INEO_HOME/instances/facebook
    PORT:    7575
    HTTPS:   8585

  > instance 'twitter'
    VERSION: $version
    PATH:    $INEO_HOME/instances/twitter
    PORT:    7474
    HTTPS:   8484
"
  done

  assert_end InstancesCorrectly
}
tests+=('InstancesCorrectly')


# ==============================================================================
# TEST VERSIONS
# ==============================================================================

VersionsWithIncorrectParameters() {
  setup

  local params=(
    'wrong' 'wrong'
    '-q' 'q'
  )

  local param
  for ((i=0; i<${#params[*]}; i+=2)); do
    assert_raises "./ineo versions ${params[i]}" 1
    assert        "./ineo versions ${params[i]}" \
"
  ERROR: Invalid argument or option: ${params[i+1]}!

  For help about the command 'versions' type:
  ineo help versions
"
  done

  assert_end VersionsWithIncorrectParameters
}
tests+=('VersionsWithIncorrectParameters')


VersionsCorrectly() {
  setup

  # Make an installation
  assert_raises "./ineo install -d $(pwd)/ineo_for_test" 0

  assert_raises "./ineo versions" 0
  assert_raises "./ineo versions -u" 0

  assert_end VersionsCorrectly
}
tests+=('VersionsCorrectly')


# ==============================================================================
# TEST SHELL
# ==============================================================================

ShellWithIncorrectParameters() {
  setup

  local params=(
    "-x" 'x'
    "-x -y" 'x'
    "-x twitter" 'x'
    "facebook twitter" 'twitter'
    "-x facebook twitter" 'x'
  )

  local i
  for ((i=0; i<${#params[*]}; i+=2)); do
    assert_raises "./ineo shell ${params[i]}" 1
    assert        "./ineo shell ${params[i]}" \
"
  ERROR: Invalid argument or option: ${params[i+1]}!

  For help about the command 'shell' type:
  ineo help shell
"
  done

  assert_end ShellWithIncorrectParameters
}
tests+=('ShellWithIncorrectParameters')


StartAShellWithoutTheRequiredParameter() {
  setup

  # Make an installation
  assert_raises "./ineo install -d $(pwd)/ineo_for_test" 0

  assert_raises "./ineo shell" 1
  assert "./ineo shell" \
"
  ERROR: shell requires an instance name!

  For help about the command 'shell' type:
  ineo help shell
"

  assert_end StartAShellWithoutTheRequiredParameter
}
tests+=('StartAShellWithoutTheRequiredParameter')


StartAShellWithANonExistentInstance() {
  setup

  # Make an installation
  assert_raises "./ineo install -d $(pwd)/ineo_for_test" 0

  assert_raises "./ineo shell twitter" 1
  assert        "./ineo shell twitter" \
"
  ERROR: There is not an instance with the name 'twitter'!

  Use 'ineo instances' to list the instances installed
"

  assert_end StartAShellWithANonExistentInstance
}
tests+=('StartAShellWithANonExistentInstance')


# ==============================================================================
# TEST CONSOLE
# ==============================================================================

ConsoleWithIncorrectParameters() {
  setup

  local params=(
    "-x" 'x'
    "-x -y" 'x'
    "-x twitter" 'x'
    "facebook twitter" 'twitter'
    "-x facebook twitter" 'x'
  )

  local i
  for ((i=0; i<${#params[*]}; i+=2)); do
    assert_raises "./ineo console ${params[i]}" 1
    assert        "./ineo console ${params[i]}" \
"
  ERROR: Invalid argument or option: ${params[i+1]}!

  For help about the command 'console' type:
  ineo help console
"
  done

  assert_end ConsoleWithIncorrectParameters
}
tests+=('ConsoleWithIncorrectParameters')


StartModeConsoleWithoutTheRequiredParameter() {
  setup

  # Make an installation
  assert_raises "./ineo install -d $(pwd)/ineo_for_test" 0

  assert_raises "./ineo console" 1
  assert "./ineo console" \
"
  ERROR: console requires an instance name!

  For help about the command 'console' type:
  ineo help console
"

  assert_end StartModeConsoleWithoutTheRequiredParameter
}
tests+=('StartModeConsoleWithoutTheRequiredParameter')


StartModeConsoleWithANonExistentInstance() {
  setup

  # Make an installation
  assert_raises "./ineo install -d $(pwd)/ineo_for_test" 0

  assert_raises "./ineo console twitter" 1
  assert        "./ineo console twitter" \
"
  ERROR: There is not an instance with the name 'twitter'!

  You can create an instance with the command 'ineo create twitter'
"

  assert_end StartModeConsoleWithANonExistentInstance
}
tests+=('StartModeConsoleWithANonExistentInstance')


# ==============================================================================
# TEST DESTROY
# ==============================================================================

DestroyWithIncorrectParameters() {
  setup

  local params=(
    "-x" 'x'
    "-x -y" 'x'
    "-x twitter" 'x'
    "facebook twitter" 'twitter'
    "-x facebook twitter" 'x'
  )

  local i
  for ((i=0; i<${#params[*]}; i+=2)); do
    assert_raises "./ineo destroy ${params[i]}" 1
    assert        "./ineo destroy ${params[i]}" \
"
  ERROR: Invalid argument or option: ${params[i+1]}!

  For help about the command 'destroy' type:
  ineo help destroy
"
  done

  assert_end DestroyWithIncorrectParameters
}
tests+=('DestroyWithIncorrectParameters')


DestroyAnInstanceWithoutTheRequiredParameter() {
  setup

  # Make an installation
  assert_raises "./ineo install -d $(pwd)/ineo_for_test" 0

  assert_raises "./ineo destroy" 1
  assert "./ineo destroy" \
"
  ERROR: destroy requires an instance name!

  For help about the command 'destroy' type:
  ineo help destroy
"

  assert_end DestroyAnInstanceWithoutTheRequiredParameter
}
tests+=('DestroyAnInstanceWithoutTheRequiredParameter')


DestroyANonExistentInstance() {
  setup

  # Make an installation
  assert_raises "./ineo install -d $(pwd)/ineo_for_test" 0

  assert_raises "./ineo destroy twitter" 1
  assert        "./ineo destroy twitter" \
"
  ERROR: There is not an instance with the name 'twitter'!

  Use 'ineo instances' to list the instances installed
"

  assert_end DestroyANonExistentInstance
}
tests+=('DestroyANonExistentInstance')


DestroyCorrectly() {
  local version
  for version in "${versions[@]}"; do
    setup

    # Make an installation
    assert_raises "./ineo install -d $(pwd)/ineo_for_test" 0

    # Test confirming without an instance running

    assert_raises "./ineo create -v $version twitter" 0

    assert_raises "echo -ne 'y\n' | ./ineo destroy twitter" 0

    assert_raises "./ineo create -v $version twitter" 0
    assert "echo -ne 'y\n' | ./ineo destroy twitter" \
"
  WARNING: Destroying the instance 'twitter' will remove all data for this instance!



  The instance 'twitter' was successfully destroyed.
"

    # Test confirming with an instance running

    assert_raises "./ineo create -v $version twitter" 0
    assert_raises "./ineo start twitter" 0

    set_instance_pid twitter
    assert_run_pid $pid

    assert_raises "echo -ne 'y\ny\n' | ./ineo destroy twitter" 0

    assert_not_run_pid $pid

    # Test forcing without an instance running

    assert_raises "./ineo create -v $version twitter" 0

    assert_raises "./ineo destroy -f twitter" 0

    assert_raises "./ineo create -v $version twitter" 0
    assert "./ineo destroy -f twitter" \
"
  The instance 'twitter' was successfully destroyed.

"

    # Test forcing with an instance running

    assert_raises "./ineo create -v $version twitter" 0
    assert_raises "./ineo start twitter" 0

    set_instance_pid twitter
    assert_run_pid $pid

    assert_raises "./ineo destroy -f twitter" 0

    assert_not_run_pid $pid
  done
  assert_end DestroyCorrectly
}
tests+=('DestroyCorrectly')


# ==============================================================================
# TEST SET-PORT
# ==============================================================================

SetPortWithIncorrectParameters() {
  setup

  local params=(
    "-x" 'x'
    "-x -y" 'x'
    "-x twitter" 'x'
    "facebook 9898 twitter" 'twitter'
    "-x facebook 9898" 'x'
  )

  local i
  for ((i=0; i<${#params[*]}; i+=2)); do
    assert_raises "./ineo set-port ${params[i]}" 1
    assert        "./ineo set-port ${params[i]}" \
"
  ERROR: Invalid argument or option: ${params[i+1]}!

  For help about the command 'set-port' type:
  ineo help set-port
"
  done

  assert_end SetPortWithIncorrectParameters
}
tests+=('SetPortWithIncorrectParameters')


SetPortWithoutTheRequireParameters() {
  setup

  # Make an installation
  assert_raises "./ineo install -d $(pwd)/ineo_for_test" 0

  assert_raises "./ineo create twitter" 0

  assert_raises "./ineo set-port" 1
  assert        "./ineo set-port" \
"
  ERROR: set-port requires an instance name and a port number!

  For help about the command 'set-port' type:
  ineo help set-port
"

  assert_raises "./ineo set-port twitter" 1
  assert        "./ineo set-port twitter" \
"
  ERROR: set-port requires an instance name and a port number!

  For help about the command 'set-port' type:
  ineo help set-port
"

  assert_end SetPortWithoutTheRequireParameters
}
tests+=('SetPortWithoutTheRequireParameters')


SetPortOnANonExistentInstance() {
  setup

  # Make an installation
  assert_raises "./ineo install -d $(pwd)/ineo_for_test" 0

  assert_raises "./ineo set-port twitter 7575" 1
  assert        "./ineo set-port twitter 7474" \
"
  ERROR: There is not an instance with the name 'twitter' or is not properly installed!

  Use 'ineo instances' to list the instances installed
"

  assert_end SetPortOnANonExistentInstance
}
tests+=('SetPortOnANonExistentInstance')


SetPortWithAnIncorrectNumberPort() {
  setup

  # Make an installation
  assert_raises "./ineo install -d $(pwd)/ineo_for_test" 0

  assert_raises "./ineo create twitter" 0

  assert_raises "./ineo set-port twitter aaa" 1
  assert        "./ineo set-port twitter aaa" \
"
  ERROR: The port must be a positive integer number!

  For help about the command 'set-port' type:
  ineo help set-port
"

  assert_end SetPortWithAnIncorrectNumberPort
}
tests+=('SetPortWithAnIncorrectNumberPort')


SetPortWithAnIncorrectOutOfRangePort() {
  setup

  # Make an installation
  assert_raises "./ineo install -d $(pwd)/ineo_for_test" 0

  assert_raises "./ineo create twitter" 0

  assert_raises "./ineo set-port twitter 65536" 1
  assert        "./ineo set-port twitter 65536" \
"
  ERROR: The port must be a number between 1 and 65535!

  For help about the command 'set-port' type:
  ineo help set-port
"

  assert_raises "./ineo set-port twitter 0" 1
  assert        "./ineo set-port twitter 0" \
"
  ERROR: The port must be a number between 1 and 65535!

  For help about the command 'set-port' type:
  ineo help set-port
"

  assert_end SetPortWithAnIncorrectOutOfRangePort
}
tests+=('SetPortWithAnIncorrectOutOfRangePort')


SetPortCorrectly() {
  local version
  for version in "${versions[@]}"; do
    setup

    # Make an installation
    assert_raises "./ineo install -d $(pwd)/ineo_for_test" 0

    # Test http port
    assert_raises "./ineo create -v $version twitter" 0

    assert_raises "./ineo set-port twitter 1" 0
    assert        "./ineo set-port twitter 1" \
"
  The http port was successfully changed to '1'.
"

    assert_raises "./ineo set-port twitter 65535" 0
    assert        "./ineo set-port twitter 65535" \
"
  The http port was successfully changed to '65535'.
"

  # Test https port
    assert_raises "./ineo set-port -s twitter 1" 0
    assert        "./ineo set-port -s twitter 1" \
"
  The https port was successfully changed to '1'.
"

    assert_raises "./ineo set-port -s twitter 65535" 0
    assert        "./ineo set-port -s twitter 65535" \
"
  The https port was successfully changed to '65535'.
"
  done
  assert_end SetPortCorrectly
}
tests+=('SetPortCorrectly')


# ==============================================================================
# TEST CLEAR-DATA
# ==============================================================================

ClearDataWithIncorrectParameters() {
  setup

  local params=(
    "-x" 'x'
    "-x -y" 'x'
    "-x twitter" 'x'
    "facebook twitter" 'twitter'
    "-x facebook" 'x'
  )

  local i
  for ((i=0; i<${#params[*]}; i+=2)); do
    assert_raises "./ineo delete-db ${params[i]}" 1
    assert        "./ineo delete-db ${params[i]}" \
"
  ERROR: Invalid argument or option: ${params[i+1]}!

  For help about the command 'delete-db' type:
  ineo help delete-db
"
  done

  assert_end ClearDataWithIncorrectParameters
}
tests+=('ClearDataWithIncorrectParameters')


ClearDataWithoutTheRequireParameters() {
  setup

  # Make an installation
  assert_raises "./ineo install -d $(pwd)/ineo_for_test" 0

  assert_raises "./ineo create twitter" 0

  assert_raises "./ineo delete-db" 1
  assert        "./ineo delete-db" \
"
  ERROR: delete-db requires an instance name!

  For help about the command 'delete-db' type:
  ineo help delete-db
"

  assert_end ClearDataWithoutTheRequireParameters
}
tests+=('ClearDataWithoutTheRequireParameters')


ClearDataOnANonExistentInstance() {
  setup

  # Make an installation
  assert_raises "./ineo install -d $(pwd)/ineo_for_test" 0

  assert_raises "./ineo delete-db twitter" 1
  assert        "./ineo delete-db twitter" \
"
  ERROR: There is not an instance with the name 'twitter' or is not properly installed!

  Use 'ineo instances' to list the instances installed
"

  assert_end ClearDataOnANonExistentInstance
}
tests+=('ClearDataOnANonExistentInstance')


ClearDataCorrectly() {
  local version
  for version in "${versions[@]}"; do
    setup

    # Make an installation
    assert_raises "./ineo install -d $(pwd)/ineo_for_test" 0

    # Test confirming without an instance running

    assert_raises "./ineo create -v $version twitter" 0
    # Create a fake directory
    assert_raises "mkdir ineo_for_test/instances/twitter/data/graph.db" 0
    assert_raises "test -d ineo_for_test/instances/twitter/data/graph.db" 0

    assert_raises "echo -ne 'y\n' | ./ineo delete-db twitter" 0

    # Create a fake directory
    assert_raises "mkdir ineo_for_test/instances/twitter/data/graph.db" 0
    assert_raises "test -d ineo_for_test/instances/twitter/data/graph.db" 0

    assert "echo -ne 'y\n' | ./ineo delete-db twitter" \
"
  WARNING: delete-db on the instance 'twitter' will remove all data for this instance!


  The data for the instance 'twitter' was successfully removed.
"

    assert_raises "test -d ineo_for_test/instances/twitter/data/graph.db" 1

    # Test confirming with an instance running

    # Create a fake directory
    assert_raises "mkdir ineo_for_test/instances/twitter/data/graph.db" 0
    assert_raises "test -d ineo_for_test/instances/twitter/data/graph.db" 0

    assert_raises "./ineo start twitter" 0

    set_instance_pid twitter
    assert_run_pid $pid

    assert_raises "echo -ne 'y\ny\n' | ./ineo delete-db twitter" 0

    assert_raises "test -d ineo_for_test/instances/twitter/data/graph.db" 1

    assert_not_run_pid $pid

    # Test forcing without an instance running

    # Create a fake directory
    assert_raises "mkdir ineo_for_test/instances/twitter/data/graph.db" 0
    assert_raises "test -d ineo_for_test/instances/twitter/data/graph.db" 0

    assert_raises "./ineo delete-db -f twitter" 0

    assert_raises "test -d ineo_for_test/instances/twitter/data/graph.db" 1

    # Create a fake directory
    assert_raises "mkdir ineo_for_test/instances/twitter/data/graph.db" 0
    assert_raises "test -d ineo_for_test/instances/twitter/data/graph.db" 0

    assert "./ineo delete-db -f twitter" \
"
  The data for the instance 'twitter' was successfully removed.
"

    assert_raises "test -d ineo_for_test/instances/twitter/data/graph.db" 1

    # Test forcing with an instance running

    # Create a fake directory
    assert_raises "mkdir ineo_for_test/instances/twitter/data/graph.db" 0
    assert_raises "test -d ineo_for_test/instances/twitter/data/graph.db" 0

    assert_raises "./ineo start twitter" 0

    set_instance_pid twitter
    assert_run_pid $pid

    assert_raises "./ineo delete-db -f twitter" 0

    assert_not_run_pid $pid

    assert_raises "test -d ineo_for_test/instances/twitter/data/graph.db" 1
  done
  assert_end ClearDataCorrectly
}
tests+=('ClearDataCorrectly')


ClearDataCorrectlyWithoutADatabaseFile() {
  local version
  for version in "${versions[@]}"; do
    setup

    # Make an installation
    assert_raises "./ineo install -d $(pwd)/ineo_for_test" 0

    # Test confirming without an instance running

    assert_raises "./ineo create -v $version twitter" 0
    assert_raises "test -d ineo_for_test/instances/twitter/data/graph.db" 1

    assert_raises "echo -ne 'y\n' | ./ineo delete-db twitter" 0

    assert "echo -ne 'y\n' | ./ineo delete-db twitter" \
"
  WARNING: delete-db on the instance 'twitter' will remove all data for this instance!


  INFO: There is not a database on the instance 'twitter', so nothing was removed.
"

    # Test confirming with an instance running

    assert_raises "./ineo start twitter" 0

    set_instance_pid twitter
    assert_run_pid $pid

    assert_raises "echo -ne 'y\ny\n' | ./ineo delete-db twitter" 0

    assert_raises "test -d ineo_for_test/instances/twitter/data/graph.db" 1

    assert_not_run_pid $pid

    # Test forcing without an instance running

    assert_raises "./ineo delete-db -f twitter" 0

    assert "./ineo delete-db -f twitter" \
"
  INFO: There is not a database on the instance 'twitter', so nothing was removed.
"

    # Test forcing with an instance running

    assert_raises "./ineo start twitter" 0

    set_instance_pid twitter
    assert_run_pid $pid

    assert_raises "./ineo delete-db -f twitter" 0

    assert_not_run_pid $pid

    assert_raises "test -d ineo_for_test/instances/twitter/data/graph.db" 1
  done
  assert_end ClearDataCorrectlyWithoutADatabaseFile
}
tests+=('ClearDataCorrectlyWithoutADatabaseFile')

# ==============================================================================
# TEST UPDATE
# ==============================================================================

UpdateWithIncorrectParameters() {
  setup

  local params=(
    "-x" '-x'
    "-x -y" '-x'
    "facebook" 'facebook'
    "facebook twitter" 'facebook'
    "-x facebook" '-x'
  )

  local i
  for ((i=0; i<${#params[*]}; i+=2)); do
    assert_raises "./ineo update ${params[i]}" 1
    assert        "./ineo update ${params[i]}" \
"
  ERROR: Invalid argument or option: ${params[i+1]}!

  For help about the command 'update' type:
  ineo help update
"
  done

  assert_end UpdateWithIncorrectParameters
}
tests+=('UpdateWithIncorrectParameters')


UpdateCorrectly() {
  setup

  # Make an installation
  assert_raises "./ineo install -d $(pwd)/ineo_for_test" 0
  assert_raises "./ineo update" 0

  setup
  assert_raises "./ineo install -d $(pwd)/ineo_for_test" 0
  old_version=$(sed -n '/^VERSION=\(.*\)$/s//\1/p' $INEO_HOME/bin/ineo)

  assert "./ineo update" \
"
  Ineo was successfully upgraded from $old_version to x.x.x
"

  assert_raises "test $(sed -n '/^VERSION=\(.*\)$/s//\1/p' $INEO_HOME/bin/ineo) = 'x.x.x'" 0

  assert_end UpdateCorrectly
}
tests+=('UpdateCorrectly')


if [[ -z "$test_name" ]]; then
  for test in "${tests[@]}"; do
    "$test"
  done
else
  "$test_name"
fi