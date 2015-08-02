#!/bin/bash

NEO4J_HOSTNAME='http://dist.neo4j.org'
DEFAULT_VERSION='2.2.2'

# ==============================================================================
# PROVISION
# ==============================================================================

versions=( "$@" )

# If there are not any argument specified then test just with default Neo4j
# version
if [ ${#versions[@]} -eq 0 ]
then
  versions=("$DEFAULT_VERSION")

# If is all then test with all Neo4j versions
elif [ ${versions[0]} = 'all' ]
then
  versions=(1.9.9 2.0.4 2.1.8 2.2.2)
fi

# Creates directories if not exists
mkdir -p tars_for_test

# If some Neo4J version has not been downloaded then try to download it, so can
# test locally reducing remote http requests.
for version in "${versions[@]}"
do
  tar_name="neo4j-community-$version-unix.tar.gz"
  if [ ! -f tars_for_test/${tar_name} ]; then
    printf "\n\nDownloading ${version}\n\n"
    if ! curl -f -o /tmp/${$}.${tar_name} ${NEO4J_HOSTNAME}/${tar_name}
    then
      printf "\n\nError downloading ${version}\nThe test has been aborted!!!\n"
      exit 0
    fi

    mv /tmp/${$}.${tar_name} tars_for_test/${tar_name}
  fi
done

set -e

# Load assert.sh library (More info: http://github.com/lehmannro/assert.sh)
. assert.sh

# ==============================================================================
# PID FUNCTIONS
# ==============================================================================

function get_instance_pid {
  local instance_name=$1
  assert_raises \
    "test -f $INEO_HOME/instances/$instance_name/data/neo4j-service.pid" 0
  local pid=$(head -n 1 $INEO_HOME/instances/$instance_name/data/neo4j-service.pid)
  echo "$pid"
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

# Install with incorrect parameters
# ------------------------------------------------------------------------------
setup

params=(
  "-e $(pwd)/ineo_for_test" 'e'
  "-e$(pwd)/ineo_for_test" 'e'
  "x -d $(pwd)/ineo_for_test" 'x'
  "x -d$(pwd)/ineo_for_test" 'x'
  "-d $(pwd)/ineo_for_test y" 'y'
  "-d$(pwd)/ineo_for_test y" 'y'
)

for ((i=0; i<${#params[*]}; i+=2))
do
  assert_raises "./ineo install ${params[i]}" 1
  assert        "./ineo install ${params[i]}" \
"
ERROR: Invalid argument or option: ${params[i+1]}!

To help about the command 'install' type:
  ineo help install
"
done

# Install with a relative directory
# ------------------------------------------------------------------------------
setup

params=(
  '-d ineo_for_test'
  '-dineo_for_test'
)

for param in "${params[@]}"
do
  assert_raises "./ineo install $param" 1
  assert        "./ineo install $param" \
"
ERROR: The directory 'ineo_for_test' is not an absolute path!

Use directories like:
  /opt/ineo
  ~/.ineo
"
done

assert_end Install on an existing directory

# Install on an existing directory
# ------------------------------------------------------------------------------
setup

assert_raises "mkdir $(pwd)/ineo_for_test" 0

params=(
  "-d $(pwd)/ineo_for_test"
  "-d$(pwd)/ineo_for_test"
)

for param in "${params[@]}"
do
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

assert_end Install on an existing directory

# Install correctly
# ------------------------------------------------------------------------------
params=(
  "-d $(pwd)/ineo_for_test"
  "-d$(pwd)/ineo_for_test"
)

for param in "${params[@]}"
do
  setup

  assert "./ineo install $param" \
"
Ineo was successfully installed in $(pwd)/ineo_for_test.

To start using the 'ineo' command reopen your terminal or enter:
  source ~/.bashrc
"

  assert_raises "test -d ineo_for_test" 0
  assert_raises "test -d ineo_for_test/bin" 0
  assert_raises "test -d ineo_for_test/instances" 0

  assert_raises \
    "grep -Fq 'export INEO_HOME=$(pwd)/ineo_for_test; export PATH=\$INEO_HOME/bin:\$PATH' ~/.bashrc" 0
done

assert_end Install correctly.

# ==============================================================================
# TEST UNINSTALL
# ==============================================================================

# Uninstall with incorrect parameters
# ------------------------------------------------------------------------------
setup

params=(
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

for ((i=0; i<${#params[*]}; i+=2))
do
  assert_raises "./ineo uninstall ${params[i]}" 1
  assert        "./ineo uninstall ${params[i]}" \
"
ERROR: Invalid argument or option: ${params[i+1]}!

To help about the command 'uninstall' type:
  ineo help uninstall
"
done

assert_end Uninstall with incorrect parameters

# Uninstall with a relative directory
# ------------------------------------------------------------------------------
setup

params=(
  '-d ineo_for_test'
  '-dineo_for_test'
)

for param in "${params[@]}"
do
  assert_raises "./ineo uninstall $param" 1
  assert        "./ineo uninstall $param" \
"
ERROR: The directory 'ineo_for_test' is not an absolute path!

Use directories like:
  /opt/ineo
  ~/.ineo
"
done

assert_end Uninstall on an existing directory

# Uninstall with a non-existent directory
# ------------------------------------------------------------------------------
setup

params=(
  "-d $(pwd)/ineo_for_test"
  "-d$(pwd)/ineo_for_test"
)

# Ensure that directory doesn't exists
assert_raises "test -d $(pwd)/ineo_for_test" 1

for param in "${params[@]}"
do
  assert_raises "./ineo uninstall $param" 1
  assert        "./ineo uninstall $param" \
"
ERROR: The directory '$(pwd)/ineo_for_test' doesn't exists!

Are you sure Ineo is installed?
"
done

assert_end Uninstall with a non-existent directory

# Uninstall with a directory that doesn't looks like an Ineo directory
# ------------------------------------------------------------------------------
setup

params=(
  "-d $(pwd)/ineo_for_test"
  "-d$(pwd)/ineo_for_test"
)

for param in "${params[@]}"
do

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
\n\n
WARNING: This action will remove everything in '$(pwd)/ineo_for_test'!
"
  # Ensure that directory exists yet
  assert_raises "test -d $(pwd)/ineo_for_test" 0


  # Uninstall saying yes to first prompt and yes to second prompt
  assert "echo -ne 'y\ny\n' | ./ineo uninstall $param" \
"
WARNING: The directory '$(pwd)/ineo_for_test' doesn't look like an Ineo directory!
\n\n
WARNING: This action will remove everything in '$(pwd)/ineo_for_test'!
\n\n
Ineo was successfully uninstalled
"
  # Ensure that directory doesn't exists
  assert_raises "test -d $(pwd)/ineo_for_test" 1
done

assert_end Uninstall with a directory that doesnt looks like an Ineo directory

# Uninstall with a directory that doesn't looks like an Ineo directory using f
# ------------------------------------------------------------------------------
setup

params=(
  "-d $(pwd)/ineo_for_test -f"
  "-d$(pwd)/ineo_for_test -f"
  "-f -d $(pwd)/ineo_for_test"
  "-f -d$(pwd)/ineo_for_test"
)

for param in "${params[@]}"
do
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

assert_end Uninstall with a directory that doesnt looks like an Ineo directory using f

# ==============================================================================
# TEST CREATE
# ==============================================================================

# Create with incorrect parameters
# ------------------------------------------------------------------------------
setup

params=(
  "-x" 'x'
  "-d -x" 'x'
  "-f -x" 'x'
  "-p7474 -x" 'x'
  "-s7878 -x" 'x'
  "-v2.2.2 -x" 'x'
  "-p7474 -s7878 -v2.2.2 -d -f -x" 'x'
  "facebook twitter" 'twitter'
  "-x facebook twitter" 'x'
  "-p7474 facebook twitter" 'twitter'
  "-p7474 -s7878 -v2.2.2 -d -f facebook twitter" 'twitter'
)

for ((i=0; i<${#params[*]}; i+=2))
do
  assert_raises "./ineo create ${params[i]}" 1
  assert        "./ineo create ${params[i]}" \
"
ERROR: Invalid argument or option: ${params[i+1]}!

To help about the command 'create' type:
  ineo help create
"
done

assert_end Create with incorrect parameters

# Set the variables to create instances
# ------------------------------------------------------------------------------

export NEO4J_HOSTNAME="file:///$(pwd)/tars_for_test"
export INEO_HOME="$(pwd)/ineo_for_test"

# Create an instance correctly with different variations of parameters
# ------------------------------------------------------------------------------

# The parameters to check are 'port' 'ssl port' 'version'
params=(
  'twitter'                        '7474' '7475' '2.2.2'
  '-p8484 twitter'                 '8484' '8485' '2.2.2'
  '-s9495 twitter'                 '7474' '9495' '2.2.2'
  '-p8484 -s9495 twitter'          '8484' '9495' '2.2.2'
  '-v1.9.9 twitter'                '7474' '7475' '1.9.9'
  '-p8484 -v1.9.9 twitter'         '8484' '8485' '1.9.9'
  '-s9495 -v1.9.9 twitter'         '7474' '9495' '1.9.9'
  '-p8484 -s9495 -v1.9.9 twitter'  '8484' '9495' '1.9.9'
)

for ((i=0; i<${#params[*]}; i+=4))
do
  setup

  port=${params[i+1]}
  ssl_port=${params[i+2]}
  version=${params[i+3]}
  config="$(pwd)/ineo_for_test/instances/twitter/conf/neo4j-server.properties"

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

assert_end Create an instance correctly with different variations of parameters

# Create an instance with a bad tar and try again with -d option
# ------------------------------------------------------------------------------
setup

# Truncate a bad version, so is possible a bad tar
rm -fr bad_tar_for_test
mkdir bad_tar_for_test

cp tars_for_test/neo4j-community-${DEFAULT_VERSION}-unix.tar.gz bad_tar_for_test

gtruncate -s20MB bad_tar_for_test/neo4j-community-${DEFAULT_VERSION}-unix.tar.gz

# Change the NEO4J_HOSTNAME for test to download the bad tar
export NEO4J_HOSTNAME="file:///$(pwd)/bad_tar_for_test"

# Make an installation
assert_raises "./ineo install -d $(pwd)/ineo_for_test" 0

# Create the instance with a bad tar version
assert "./ineo create -v$DEFAULT_VERSION twitter" \
"
ERROR: The tar file 'neo4j-community-$DEFAULT_VERSION-unix.tar.gz' can't be extracted!

Try run the command 'create' with the -d option to download the tar file again

"
# Ensure the bad tar version of neo4j was downloaded
assert_raises \
  "test -f $(pwd)/ineo_for_test/neo4j/neo4j-community-$DEFAULT_VERSION-unix.tar.gz" 0

# Ensure the instance doesn't exists
assert_raises "test -d $(pwd)/ineo_for_test/instances/twitter" 1

# The bad tar now must be good
rm -fr bad_tar_for_test
mkdir bad_tar_for_test

cp tars_for_test/neo4j-community-${DEFAULT_VERSION}-unix.tar.gz bad_tar_for_test

# Create the instance with a good tar version
assert "./ineo create -d -v$DEFAULT_VERSION twitter" \
"
The instance twitter was created successfully

"
# Ensure the correct neo4j version was downloaded
assert_raises \
  "test -f $(pwd)/ineo_for_test/neo4j/neo4j-community-$DEFAULT_VERSION-unix.tar.gz" 0

# Ensure neo4j exists
assert_raises "test -f $(pwd)/ineo_for_test/instances/twitter/bin/neo4j" 0

# Restore the correct NEO4J_HOSTNAME for test
export NEO4J_HOSTNAME="file:///$(pwd)/tars_for_test"

assert_end Create an instance with a bad tar and try again with -d option

# Create an instance on a existing directory and try again with -f option
# ------------------------------------------------------------------------------
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
  "test -f $(pwd)/ineo_for_test/neo4j/neo4j-community-2.2.2-unix.tar.gz" 0

# Ensure the instance directory is empty yet
assert_raises "test $(ls -A ineo_for_test/instances/twitter)" 1

# Create the instance with -f option
assert "./ineo create -f twitter" \
"
The instance twitter was created successfully

"

# Ensure neo4j exists
assert_raises "test -f $(pwd)/ineo_for_test/instances/twitter/bin/neo4j" 0

assert_end Create an instance with on a existing directory and try again with -f option

# ==============================================================================
# TEST INSTANCE ACTIONS (START, STATUS, RESTART, STOP)
# ==============================================================================

actions=('start' 'status' 'restart' 'stop')

# Actions with incorrect parameters
# ------------------------------------------------------------------------------
setup

params=(
  "-x" 'x'
  "-x -y" 'x'
  "-x twitter" 'x'
  "facebook twitter" 'twitter'
  "-x facebook twitter" 'x'
)

for ((i=0; i<${#actions[*]}; i+=1)); do
  for ((j=0; j<${#params[*]}; j+=2)); do
    assert_raises "./ineo ${actions[i]} ${params[j]}" 1
    assert        "./ineo ${actions[i]} ${params[j]}" \
"
ERROR: Invalid argument or option: ${params[j+1]}!

To help about the command '${actions[i]}' type:
  ineo help ${actions[i]}
"
  done
done

assert_end Actions with incorrect parameters

# Actions on a non-existent instance
# ------------------------------------------------------------------------------
setup

# Make an installation
assert_raises "./ineo install -d $(pwd)/ineo_for_test" 0

for ((i=0; i<${#actions[*]}; i+=1)); do
  assert_raises "./ineo ${actions[i]} twitter" 1
  assert        "./ineo ${actions[i]} twitter" \
"
ERROR: There is not an instance with the name 'twitter'!

You can create an instance with the command 'ineo create twitter'
"
done

assert_end Actions on a non-existent instance

# Actions on a not properly installed instance
# ------------------------------------------------------------------------------
setup

# Make an installation
assert_raises "./ineo install -d $(pwd)/ineo_for_test" 0

mkdir ineo_for_test/instances/twitter

for ((i=0; i<${#actions[*]}; i+=1)); do
  assert_raises "./ineo ${actions[i]} twitter" 1
  assert        "./ineo ${actions[i]} twitter" \
"
ERROR: The instance 'twitter' seems that is not properly installed!

You can recreate the instance with the command 'ineo create -f twitter'
"
done

assert_end Actions on a not properly installed instance

# Execute actions correctly
# ------------------------------------------------------------------------------
setup

# Make an installation
assert_raises "./ineo install -d $(pwd)/ineo_for_test" 0

assert_raises "./ineo create twitter" 0

# start
assert_raises "./ineo start twitter" 0
pid=$(get_instance_pid twitter)
assert_run_pid $pid

# status running
assert "./ineo status twitter" \
"
> status 'twitter'
  Neo4j Server is running at pid $pid
"

# restart
assert_raises "./ineo restart twitter" 0
pid=$(get_instance_pid twitter)
assert_run_pid $pid

# status running
assert "./ineo status twitter" \
"
> status 'twitter'
  Neo4j Server is running at pid $pid
"

# stop
assert_raises "./ineo stop twitter" 0
assert_not_run_pid $pid

# status not running
assert "./ineo status twitter" \
"
> status 'twitter'
  Neo4j Server is not running
"

assert_end Execute actions correctly

# Execute actions on various instances correctly
# ------------------------------------------------------------------------------
setup

# Make an installation
assert_raises "./ineo install -d $(pwd)/ineo_for_test" 0

# Test confirming
assert_raises "./ineo create -p7474 twitter" 0
assert_raises "./ineo create -p7476 facebook" 0

# start
assert_raises "echo -ne 'y\n' | ./ineo start" 0

pid_twitter=$(get_instance_pid twitter)
assert_run_pid $pid_twitter

pid_facebook=$(get_instance_pid facebook)
assert_run_pid $pid_facebook

# status running
assert "./ineo status" \
"
> status 'facebook'
  Neo4j Server is running at pid $pid_facebook


> status 'twitter'
  Neo4j Server is running at pid $pid_twitter
"

# restart
assert_raises "echo -ne 'y\n' | ./ineo restart" 0

pid_twitter=$(get_instance_pid twitter)
assert_run_pid $pid_twitter

pid_facebook=$(get_instance_pid facebook)
assert_run_pid $pid_facebook

# status running
assert "./ineo status" \
"
> status 'facebook'
  Neo4j Server is running at pid $pid_facebook


> status 'twitter'
  Neo4j Server is running at pid $pid_twitter
"

# stop
assert_raises "echo -ne 'y\n' | ./ineo stop" 0
assert_not_run_pid $pid_twitter
assert_not_run_pid $pid_facebook

# status not running
assert "./ineo status" \
"
> status 'facebook'
  Neo4j Server is not running


> status 'twitter'
  Neo4j Server is not running
"

# Test forcing with -q

# start
assert_raises "./ineo start -q" 0

pid_twitter=$(get_instance_pid twitter)
assert_run_pid $pid_twitter

pid_facebook=$(get_instance_pid facebook)
assert_run_pid $pid_facebook

# status running
assert "./ineo status" \
"
> status 'facebook'
  Neo4j Server is running at pid $pid_facebook


> status 'twitter'
  Neo4j Server is running at pid $pid_twitter
"

# restart
assert_raises "./ineo restart -q" 0

pid_twitter=$(get_instance_pid twitter)
assert_run_pid $pid_twitter

pid_facebook=$(get_instance_pid facebook)
assert_run_pid $pid_facebook

# status running
assert "./ineo status" \
"
> status 'facebook'
  Neo4j Server is running at pid $pid_facebook


> status 'twitter'
  Neo4j Server is running at pid $pid_twitter
"

assert_raises "./ineo stop -q" 0
assert_not_run_pid $pid_twitter
assert_not_run_pid $pid_facebook

# status not running
assert "./ineo status" \
"
> status 'facebook'
  Neo4j Server is not running


> status 'twitter'
  Neo4j Server is not running
"

assert_end Execute actions on various instances correctly

# ==============================================================================
# TEST INSTANCES
# ==============================================================================

# Instances with incorrect parameters
# ------------------------------------------------------------------------------
setup

params=(
  'wrong'
  '-q'
)

for ((i=0; i<${#params[*]}; i+=1))
do
  assert_raises "./ineo instances ${params[i]}" 1
  assert        "./ineo instances ${params[i]}" \
"
ERROR: Invalid argument or option: ${params[i]}!

To help about the command 'instances' type:
  ineo help instances
"
done

assert_end Instances with incorrect parameters

# Instances correctly
# ------------------------------------------------------------------------------
setup

# Make an installation
assert_raises "./ineo install -d $(pwd)/ineo_for_test" 0

assert_raises "./ineo create -p7474 -s8484 twitter" 0
assert_raises "./ineo create -p7575 -s8585 facebook" 0

assert_raises "./ineo instances" 0
assert        "./ineo instances" \
"
> instance 'facebook'
  VERSION: 2.2.2
  PATH:    /Users/carlosforero/shell/ineo/ineo_for_test/instances/facebook
  PORT:    7575
  HTTPS:   8585

> instance 'twitter'
  VERSION: 2.2.2
  PATH:    /Users/carlosforero/shell/ineo/ineo_for_test/instances/twitter
  PORT:    7474
  HTTPS:   8484
"

assert_end Instances correctly

# ==============================================================================
# TEST VERSIONS
# ==============================================================================

# Versions with incorrect parameters
# ------------------------------------------------------------------------------
setup

params=(
  'wrong'
  '-q'
)

for ((i=0; i<${#params[*]}; i+=1))
do
  assert_raises "./ineo versions ${params[i]}" 1
  assert        "./ineo versions ${params[i]}" \
"
ERROR: Invalid argument or option: ${params[i]}!

To help about the command 'versions' type:
  ineo help versions
"
done

assert_end Versions with incorrect parameters

# Versions correctly
# ------------------------------------------------------------------------------
setup

# Make an installation
assert_raises "./ineo install -d $(pwd)/ineo_for_test" 0

assert_raises "./ineo versions" 0
assert        "./ineo versions" \
"
The Neo4J versions available at Jun 3, 2015:
1.9.9
2.0.4
2.1.8
2.2.2

More information about Neo4j releases in: http://neo4j.com/download/other-releases

"
assert_end Versions correctly

# ==============================================================================
# TEST DESTROY
# ==============================================================================

# Destroy with incorrect parameters
# ------------------------------------------------------------------------------
setup

params=(
  "-x" 'x'
  "-x -y" 'x'
  "-x twitter" 'x'
  "facebook twitter" 'twitter'
  "-x facebook twitter" 'x'
)

for ((i=0; i<${#params[*]}; i+=2)); do
  assert_raises "./ineo destroy ${params[i]}" 1
  assert        "./ineo destroy ${params[i]}" \
"
ERROR: Invalid argument or option: ${params[i+1]}!

To help about the command 'destroy' type:
  ineo help destroy
"
done

assert_end Destroy with incorrect parameters

# Destroy a non-existent instance
# ------------------------------------------------------------------------------
setup

# Make an installation
assert_raises "./ineo install -d $(pwd)/ineo_for_test" 0

assert_raises "./ineo destroy twitter" 1
assert        "./ineo destroy twitter" \
"
ERROR: There is not an instance with the name 'twitter'!

Use 'ineo instances' to list the instances installed
"

assert_end Destroy a non-existent instance

# Destroy correctly
# ------------------------------------------------------------------------------
setup

# Make an installation
assert_raises "./ineo install -d $(pwd)/ineo_for_test" 0

# Test confirming without an instance running

assert_raises "./ineo create twitter" 0

assert_raises "echo -ne 'y\n' | ./ineo destroy twitter" 0

assert_raises "./ineo create twitter" 0
assert "echo -ne 'y\n' | ./ineo destroy twitter" \
"
WARNING: Destroying the instance 'twitter' will remove all data for this instance!



The instance 'twitter' was successfully destroyed.

"

# Test confirming with an instance running

assert_raises "./ineo create twitter" 0
assert_raises "./ineo start twitter" 0

pid=$(get_instance_pid twitter)
assert_run_pid $pid

assert_raises "echo -ne 'y\ny\n' | ./ineo destroy twitter" 0

assert_not_run_pid $pid

# Test forcing without an instance running

assert_raises "./ineo create twitter" 0

assert_raises "./ineo destroy -f twitter" 0

assert_raises "./ineo create twitter" 0
assert "./ineo destroy -f twitter" \
"
The instance 'twitter' was successfully destroyed.

"

# Test forcing with an instance running

assert_raises "./ineo create twitter" 0
assert_raises "./ineo start twitter" 0

pid=$(get_instance_pid twitter)
assert_run_pid $pid

assert_raises "./ineo destroy -f twitter" 0

assert_not_run_pid $pid

assert_end Destroy correctly