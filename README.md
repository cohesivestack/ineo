# ineo

A simple but useful Neo4j instance manager

Neo4j is a great graph database, however its architecture was designed to work with just one database process for each application. This issue is a limitation when we are developing an application and need an environment for testing and developing, or just when we are creating various applications.

Ineo figure out this limitation allowing to manage different Neo4j instances on different ports.

## Installation

1. Execute the bellow line on your terminal:

   ```
   curl -sSL http://getineo.cohesivestack.com | bash -s install
   ```

2. Restart your terminal or execute the bellow line:

    ```
    source ~/.bash_profile
    ```

## How to use

### Create an instance

Imagine that you need a database for an application called *my_db*:

```
$ ineo create my_db

  The instance my_db was created successfully
```

### Show instance information

Show the information about the recently created instance:

```
$ ineo instances

  > instance 'my_db'
    VERSION: 2.2.2
    PATH:    /home_path/.ineo/instances/my_db
    PORT:    7474
    HTTPS:   7475
```  

Ineo downloaded the last available version of Neo4j and created an instance database ready to use on the port 7474 and 7475 for ssl.

### Start instance

Start the database instance for using

```
$ ineo start my_db

  start 'my_db'
  Starting Neo4j Server...WARNING: not changing user
process [19773]... waiting for server to be ready....... OK.
http://localhost:7474/ is ready.
```

### Show instance status

Show the status of the database instance

```
$ ineo status my_db

  status 'my_db'
  Neo4j Server is running at pid 19773
```

### Stop instance

Stop the database instance

```
$ ineo stop my_db

  status 'my_db'
  Neo4j Server is running at pid 19773
```

### Restart instance

Also is possible restart a database instances

```
$ ineo restart my_db
```

## Using with multiple instances

The main objetive of Ineo is managing different Neo4j instances.

### Create an instance with specific port

Imagine that you want create an instance for testing. This should be created with another http port, so you both instances can be running simultaneously.

```
$ ineo create -p8486 my_db_test

  The instance my_db_test was created successfully
```

Now if you show the information about instances:

```
$ ineo instances

  > instance 'my_db'
    VERSION: 2.2.2
    PATH:    /home_path/.ineo/instances/my_db
    PORT:    7474
    HTTPS:   7475

  > instance 'my_db_test'
    VERSION: 2.2.2
    PATH:    /home_path/.ineo/instances/my_db_test
    PORT:    8486
    HTTPS:   8487
```

### Start multiple instances

All instances can be started using the command `start` without instance name.

```
$ ineo start

  WARNING: A Neo4j instance name is not specified!

  Are you sure you want to start all instances? (y/n) y


  start 'my_db'
  Starting Neo4j Server...WARNING: not changing user
process [20790]... waiting for server to be ready....... OK.
http://localhost:7474/ is ready.


  start 'my_db_test'
  Starting Neo4j Server...WARNING: not changing user
process [20930]... waiting for server to be ready....... OK.
http://localhost:8485/ is ready.
```

### Show status for multiple instances

Is possible show the status of all instances using the command `stop` without instance name.

```
$ ineo status

  status 'my_db'
  Neo4j Server is running at pid 20790


  status 'my_db_test'
  Neo4j Server is running at pid 20930
```

### Stop multiple instances

All instances can be stopped using the command `stop` without instance name.

```
$ ineo stop

  WARNING: A Neo4j instance name is not specified!

  Are you sure you want to stop all instances? (y/n) y


  stop 'my_db'
  Stopping Neo4j Server [20790].... done


  stop 'my_db_test'
  Stopping Neo4j Server [20930].... done
```

### Restart multiple instance

Also is possible restart multiple instances using the command `restart` without instance name.

```
$ ineo restart
```

## Installing a specific version

The command `create` always use the last Neo4j version available at the date of Ineo version. However is possible to specify another version using the option `-v`

```
ineo create -v 2.1.8
```

### The command versions

The command `versions` show all Neo4j versions available at the date of Ineo version.

```
$ ineo versions
```

## Other commands

### set-port

You can change the port to a specific instance.

```
$ ineo set-port my_db 9494
```

The ssl port as well.

```
$ ineo set-port -s my_db 9494
```

### destroy

Destroying a neo4j instance.

```
$ ineo destroy my_db
```

The above line remove all files related to the instance my_db

### delete-db

Delete the database files without destroy the instance.

```
$ ineo delete-db my_db
```

### update

Check for Ineo (not Neo4j) new versions and updating it if there is some available

```
$ ineo update
```

### uninstall

Uninstall Ineo. The command ask if you want to delete the instances with their data.

```
$ ineo uninstall
```

## The command install

There is a command to install Ineo. Use this command only if you don't have already installed Ineo.

```
$ ineo install
```

### Installing in a specific directory

Ineo is installed in `$HOME/.ineo` by default, however is possible to specify another directory using the option `-d`.

```
$ install -d ~/.ineo-custom-path
```

If you installing from curl:

```
$ curl -sSL http://getineo.cohesivestack.com | bash -s install -d ~/.ineo-custom-path
```

## Contributing

Any issue on [https://github.com/carlosforero/ineo/issues](https://github.com/carlosforero/ineo/issues)

All code contributions are welcome. The rules are:

* Fork the repository
* Always add or modify the test on `test.sh`
* Use correctly indentation (2 spaces) and name conventions
* Request a pull request

## License

Copyright © 2015 Carlos Forero

Ineo is released under the MIT License.