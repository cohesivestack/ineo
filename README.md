# ineo: A simple but useful neo4j version manager

Neo4j is a great graph database, however its architecture was designed to work
with one database process by application. This issue is a limitation when
we are developing an application and need the test and development environments,
or just when we are developing various applications.

Ineo figure out this limitation allowing to manage differents Neo4j instances on
differents ports.

# Installation

```
$ \curl -sSSL https://raw.githubusercontent.com/carlosforero/ineo/master/ineo | bash setup
```

# How to use

## Creating instances

```
$ ineo create <instance_name> <port> <neo4j version (optional)>
```

Examples:

Imagine that you are developing the facebook and twitter application, and you
need the development and test environmente by each one.

```
$ ineo create facebook_development 7777

$ ineo create facebook_test 7776

$ ineo create twitter_development 7778

$ ineo create twitter_test 7779
```

Note: Each instance must have a unique name, however can exists two different
instances with the same port although these can't to run at the same time

## Running an instance

```
$ ineo start <instance_name>
```

Imagine that you want to run two instances

Example:

```
$ ineo start facebook_development

$ ineo start twitter_test
```

## Checking the status

```
$ ineo status <instance_name>
```

Example:

```
$ ineo status facebook_test
```

## Stopping instances

```
$ ineo stop <instance_name>
```

Example:

```
$ ineo stop twitter_test
```

## Destroying instances

```
$ ineo destroy <instance_name>
```


# Developing

* To test is necessary have installed the `truncate` command

