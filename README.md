# FlaskBB Docker Swarm

Deploy FlaskBB into a docker swarm, using Traefik as the entrypoint.

## Motivations

I created my own docker swarm at home to play with it and get to know it a bit better.
However, I had only deployed trivial applications into it. I decided deploying FlaskBB
(which I contribute to) would be good practice for future endeavors. I know the application
well enough to debug stuff and there's just enough moving parts to make it interesting without
completely overwhelming me.


## Foreward

I encourage you to read this entire document as well as the accompanying code before getting
started. If you do not understand something, I encourage you to do some research on it  -- e.g.
if you are unfamiliar with the `python -c` invocation, take a gander at
[the Python CLI docs](https://docs.python.org/3/using/cmdline.html). If after research something
is still unclear, you can file an issue or drop a line at me either on 
[twitter](https://twitter.com/just_anr) or catch me on the #FlaskBB IRC channel on the freenode
servers (though, I'm not always there).

I've not included instructions on any of the follow:

* Setting up docker swarm
* Setting up traefik on the swarm
* Setting up a database
* Setting up portainer
* Curing frustrations with a mixed drink

All of these are well documented else where and reachable with targeted searches (using those
bullet points above should suffice).

That said, I've included notes specific to these technologies where I feel they are appropriate
(e.g. docker secrets, docker networks and how they relate to traefik) in hopes to make things
clearer for the reader, and potentially improve someone's life when they are struggling with
one of these (future me, most likely).

I'll note that you *do not* need to mimic my setup, especially if you will have a hard time coming by four VMs (at least, I also have a VM for my database). A single node docker swarm cluster is more than viable for setting this up (and that is infact how I debugged an issue I ran into, so I suppose I technically have *two* swarm clusters), though I would definitely suggest setting up a multi host swarm if possible.

A final thing before we get started, I've assumed that not only will redis be used but that it'll also be managed by the docker swarm. If either of the assumptions are wrong, feel free to adjust as necessary (either turning off redis in the flaskbb config or if you're running a non-swarm managed instance, not creating the redis network).


## Included

* Docker compose file, used for stack deploy
* Dockerfiles
    * FlaskBB
    * nginx
* Sample configs
    * flaskbb
    * uwsgi
    * nginx site conf
* Launch script
* Extra requirements not included in FlaskBB (postgres + uwsgi)

## You'll need

* Docker, needs to be able to run swarm and use swarm configs
* Access to the docker swarm manager
* Traefik attached to the swarm
* FlaskBB source code
* A database (I choose Postgres, but any *server* will be fine, just don't use sqlite)
* A local registry (if you're doing a multi node docker swarm, if it is single node then this is optional)
* Some paitence

### A note on databases

The reason you cannot use sqlite in this setup is because the actual FlaskBB app will be replicated and celery will exist in a separate container. If you try really hard, you might be able to get sqlite working for this, however I recommend just setting up postgres and being done with it.

If you do not have the ability to run a database (or if you're lazy, or just testing this out so you don't want a bunch of infrastructure lying around when you're done), I recommend pulling the postgres docker image and getting it set up the way you like.

I choose postgres as it's the database I'm most familiar with. I run it in a VM with 8gb ram, 100gb space and 2 cores, since I'm not exactly pushing anything to its limits this works for me.

### Why a local registry

The reason a local registry is needed for multi node swarms is that you need to distribute the image to each node that will run the image. SSHing into each host and building the image is a pain. 

I won't go into setting up a registry here, but I will note it's worth setting one up for testing purposes. I choose to place my images in a regular named volume so they persist between restarts. 

I also enabled TLS for the registry via a self signed cert, which required distributing that cert to each host in the swarm and running `update-ca-certificate` (as I'm using Ubuntu server as my host base, if you're running a RHEL/CentOS based swarm, I trust you know what to do there), I also needed to do this on my desktop and laptop as they communicate with the local registry.

## Some Nice To Haves

* Portainer running on a swarm manager
* A registry UI (I used hyper/docker-registry-web)

## My Setup

* Docker 17.09.0-ce on all hosts
    * One manager
    * Three workers
* Python 3.6 (base of the container)
* Portainer to manage all of this (running on swarm manager)
* Traefik, container version v1.4 (running on swarm manager)
* Registry V2 container (running on swarm manager)
* Jack and Coke (actually Dr Pepper and Maker's Mark)

The reason for running Portainer, Traefik and the Registry on the Swarm Manager (which is usually discouraged) is that I use that host as a bastion host for my swarm. All traffic is directed there via DNS in my apartment (I used a wildcard CNAME to handle everything under the hostname). I could likely move the registry off and forward everything to it via Traefik, however I don't think moving Traefik or Portainer would be very friendly (not even sure Portainer would be possible since it makes changes to the swarm and only a manager node can do that).

## Instructions

I've done most of the hard work, including beating my head against the wall when it worked locally
but not deployed into my personal swarm, however, this is not just a turn key solution.

If you are running portainer on your swarm cluster, feel free to use that to set secrets, configs, networks
and deploy the stack (I did). However, I've included the actual commands that need to be run 
in case you have decided against portainer or are running the swarm locally.

### Step 1: Secrets

I used Python 3.6's `secrets` module to handle generating secret keys. For URI secrets, I just entered them. As a heads up, docker secrets are immutable and encrypted at rest, so if you need to know what's contained in them (I'm sure you have a valid reason), you'll need to store them in an unencrypted fashion someplace else.

To create a secret with Docker Swarm, on a manager node run:

```bash
docker secret create <name> [secret | -]
```

By supplying `-` as the secret, `docker secret create` will read from stdin, so we can create secret
tokens using:

```bash
python3.6 -c "import secrets; print(secrets.token_hex())" | docker secret create <name> -
```

These keys will need to be generated for the names:

* `flaskbb_secret_key`
* `flaskbb_wtf_csrf_secret`

The other keys -- `flaskbb_postgres_connection` (which is poorly named, sorry) and `redis_url` --
these are just URIs to the database and redis instance you'll be using. The reason for making them
secrets rather than part of the config is that they might contain a password, which shouldn't be
stored in plain text.

#### On Docker Secrets

**Docker secrets only work in swarm mode.** If you are playing around locally, I encourage
you to turn your computer into a single node swarm cluster by running `docker swarm init`, you can always turn off swarm with `docker swarm leave` (you may need to use the `--force` flag, but if you do I suggest researching *why* you needed to use it).

Docker Secrets are an easy way to manage your confidental settings in a docker swarm. Docker takes
care to not allow them to leak. However, if you do something to leak it in application code (e.g.
send it to your logs), then you should take care to eliminate the leak and rotate the secret.

Rotating a secret isn't the easiest thing in the world, you need to create a new secret, potentially
updating whatever the secret tied to (database, redis, etc), and then run a `docker service update`.

The [docker secrets](https://docs.docker.com/engine/swarm/secrets/) documentation contains more
information on management and rotation of secrets, as well as other important information
about secrets.

### Step 2: Configs

**Docker configs only work in swarm mode.** See the note in secrets above.

Configs are similar to secrets, except they aren't encrypted at rest, meaning you can always see what's contained in them (using `docker config inspect --pretty <name>`), but like secrets they are immutable.

Creating a config is similar to creating a secret: `docker config create <name> [ config | - ]`. For this application, I decided on three configs:

* flaskbb-app
* flaskbb-uwsgi
* flaskbb-nginx

The motivation for this is not needing to rebuild every time I make a change to a config because configs and application code change at different rates. It's possible to instead use a volume (potentially a NFS volume) and store the configs there, mounting them where necessary to be useful, but configs guarantee immutability and are less messy than targeted volume mounts in my opinion.

I've included what *I've* used for configs in the repo, and I suggest making changes as you see fit with them.  You will need to setup the server name as I've not included that in the configs as it's specific to my own network.

If you decide to roll with them, or create your own, you can use `docker config create <name> - < path/to/config` to avoid any copy-paste errors when creating the actual config (just make sure the file is finalized before you run that, thus avoiding confusion that I may or may not have had when setting this up).

#### flaskbb-app

The `flaskbb-app` config is largely the default generated from `flaskbb makeconfig`, just updated to read secrets where appropriate. I don't run a mail server or use the mailing tasks in Flaskbb, but if I did, parts of that would read from secrets where needed as well.

#### flaskbb-uwsgi

The `flaskbb-uwsgi` config is a pretty standard, but I feel a few things are worth noting:

* `lazy = true` If this isn't used, uwsgi will create the application in the master before forking workers. Normally, I'd be all for this but this causes things like database connection pooling to be shared across all workers. However, I ended up getting an error in the pool and that took down all the workers for that node. The exact error and more details can be found on this [stackoverflow question](https://stackoverflow.com/questions/22752521/uwsgi-flask-sqlalchemy-and-postgres-ssl-error-decryption-failed-or-bad-reco)

* `uid` and `gid` I'm a big believer in the least privilege principle. By default docker containers run as root. Not just any root, but the root on the host it is running on (since it's the same kernel, it's the same root). If there's an issue that allows a user to run arbitrary code in my container, I'd rather them only be able to damage things related to the application rather than everything.

* `harakiri`, `harakiri-verbose` and `max-requests` these are all related to worker life times. `harakiri` is a setting to kill any worker that takes longer than the amount (in seconds) to respond to an HTTP request. 60 seconds is multiple lifetimes in terms of the web and this could be lowered to something closer to 10 seconds. `max-requests` is how many requests a single worker will handle before being recycled. I set this to avoid any possible memory leaks that may be present. Yes it's better to hunt them down and fix them, but I don't want to do that in a production-esque setting.

There are many more setting that can be set, however I'll leave it to you to poke through the [uWSGI documentation](https://uwsgi-docs.readthedocs.io/en/latest/). I will note that it isn't the friendliest documentation in the world.

#### flaskbb-nginx

Finally, the `flaskbb-nginx` config is just a barebones reverse proxy to the FlaskBB App service that also serves the static content. 

It is possible to set up traefik to partition routing based on path components, and that's something I'm looking at for the future. It's also possible to have uWSGI serve static content but I'd rather uWSGI focus on serving my application rather than dual purpose as both an application and static content server (however, that does alleviate needing the nginx container, and rebuilding both when content is updated).


### Step 3: Networks

I've marked the networks in the docker-compose file as external because the application stack shouldn't be concerned with how its network is configured. Arguably, the application's own network should be in the docker-compose file. I'll leave that distinction up to you and feel free to make any changes you feel appropriate to them.

I've used three networks here:

1. `traefik-net` this is the network for any application that will accept outside traffic, I use it exclusively for this purpose. 
2. `redis-net` for anything that wants to connect to my redis instances
3. `flaskbb` exclusively for FlaskBB

This helps me keep track of who is talking to who. However, this partitioning scheme caused me a great deal of frustration until I figured out what was going on (see the subheader below).

To create a docker network, it's `docker network create` (probably no surprises there, the docker commands are very uniform). I've chosen to create these networks as `overlay`, more details about the different types of networks can be found in [this blog post](https://blog.docker.com/2016/12/understanding-docker-networking-drivers-use-cases/). But the short of it is that `overlay` helps manage multihost services (read load balanced containers).

```bash
docker network create -d overlay traefik-net
docker network create -d overlay redis-net
docker network create -d overlay flaskbb
```

#### HELP! I'm getting a gateway timeout from Traefik!

This should be handled by the docker-compose as written, but you might be getting this from another stack you're attempting to deploy. Plus, it'll help me in future when I get the same error but can't remember how I fixed it.

The issue: Traefik is attempting to proxy traffic to a container that exists on two docker network. However, it's decided to pick the network that it isn't on, so it can't actually reach the container which causes a gateway timeout.

There are two solutions:

1. Run all containers on the same network. This didn't sit well with me, so I choose not to do that. If you're fine with it, this is a workable solution.
2. Label the service or container with `"traefik.docker.network=traefik-net"` (the last part should be changed to whatever network traefik lives on). However, this is also caused an issue for me until I figured out that I should quote it.

### Step 4: Build the containers

Now, we need to build the containers. I've not included a reference to the FlaskBB source in the repo as it's a moving target, but the source is a requirement for building the containers.

I've choosen to use a multi-stage image to reduce the size of the final image (additionally, I could have used alpine instead of the Ubuntu base to reduce even further). However, as long as your docker version is new enough to handle multi stage builds, you'll reap the benefits and not need to be aware of this at all.

To build the images, clone FlaskBB into `flaskbb-swarm/flaskbb` so it exists along side the Dockerfiles, scripts directory and configs directory. After that, you'll need to run:

```bash
docker build -t flaskbb-app -f Dockerfile.app .
docker build -t flaskbb-nginx -f Dockerfile.nginx .
```

If you're running a registry, prefix the image name with the path to the registry. I'd also recommend namespacing the images by replacing the `-` with a `/`, but only if you prefer. For me, this ended up looking like:

```bash
docker build -t lab.home.firelink.in/flaskbb/app -f Dockerfile.app .
docker built -t lab.home.firelink.in/flaskbb/nginx -f Dockerfile.nginx .
```

I'd strongly urge you to tag these images as well, the first build as `flaskbb-app:1` and so on, and remember to retag latest when you build as well. If you didn't specify a tag at build, you can apply a tag afterwards with `docker tag <imagename> <newimagename>:<tag>`.

If you're running a registry, you'll also want to push these images there. Luckily, docker makes this easy and you can do `docker push <imagename>` and that will push all versions of that image to the registry.

#### Why multi stage builds

Reducing image size is the number one motivator, but also not leaving more software than necessary in the container (which fewer potential bugs and attack vectors).

Previously, separting build time needs from run time needs was complicated -- [see Glyph's article on it.](https://glyph.twistedmatrix.com/2015/03/docker-deploy-double-dutch.html) -- meaning that doing it was prohibitive (read: I didn't do it because I didn't want to deal with the complexity).

However, with multistage builds, we can build everything in one stage and then copy only what we need into the next stage. In FlaskBB's case (and more generally, most Python applications) this is creating a wheelhouse and then copying that to the runtime stage, installing from the wheels and then deleting the wheelhouse when we're finished with it.

#### Included Python Envvars

I've included `PYTHONDONTWRITEBYTECODE` and `PYTHONUNBUFFERED` in the images.

Since containers are [cattle not kittens](http://etherealmind.com/cattle-vs-kittens-on-cloud-platforms-no-one-hears-the-kittens-dying/), if you need a new one you make a new one and it gets a clean environment. This means any benefit that the Python bytecode files would normally bring you (slightly faster startup times) doesn't exist anymore, and chances are you're either scaling up a service which means each container would need to generate its own bytecode or you're deploying a new instance in which case the bytecode would need to be regenerated anyways.

As for `PYTHONUNBUFFERED` that's an old habit when dealing with Python processes that log to stdout. I've found that it ends up fixing a few issues that crop up now and then with Python buffering output until it has finally decided that it's time to push it all out.

### Step 5: Deploy it!

If you have everything in place -- swarm, redis, traefik, configs, networks and secrets -- then it is time to deploy. Adjust the details in the `docker-compose.yml` file as you see fit -- in particular, the image tag for the flaskbb-app, flaskbb-celery and flaskbb-nginx services, flaskbb-app and flaskbb-celery 


By default, the FlaskBB app container will be deployed with three replicas, the celery with one replica and the nginx container with one replica. And each will reserve a quarter of a CPU with a restriction of up to half a cpu (I've not done enough analysis to determine appropriate memory limits), and restart policy of:

* condition: on-failure (the container exited with a non-zero exit code)
* delay: 2s (waits two seconds between restarts)
* max\_attempts: 3 (only restart three times -- eventually you'll need to give up rather than trying again and again)
* wait: 30s (wait 30 seconds before deciding if something has failed, this could be brought down as most of these containers will fail nearly immediately)

I've left all the labels I've used personally other than purely internal labels (I apply several labels that are potentially interesting to me, but only to me).

If you're running a single node cluster, you'll need to adjust the placement constraint. `node.role != manager` means never deploy this to a manager node. However, in a single node cluster you're node is a manager and the only deployment target.

Now all that's left is `docker stack deploy -c docker-compose.yml flaskbb`. Assuming that everything has been set up correctly and you haven't fiddled too much from the original, you'll now be able to access your very own FlaskBB instance. Of course, you'll need some sort of DNS resolution to help with this. In my case, I run internal DNS so I get that "for free" (only since I apparently don't value my own time) but an `/etc/hosts` entry will work as well.

If you haven't setup everything correctly or you have fiddled a bit too much, double check everything.

Helpful hints here are:

* The traefik dashboard. What IP does Traefik say it's trying to proxy to?
* `docker network inspect traefik-net` will reveal what containers are on the network and their IPs
* `docker service logs <service-name>` will show the stdout logs for the container -- add `-f` to follow the logs
* Add `--debug` to the traefik container will show way more information, as well as setting `--loglevel` lower (or at all, the official guide doesn't show this setting at all) -- just be sure to run `docker service logs -f traefik`
* Ensure your redis and database instances are reachable from the nodes that containers are working on.

## Other stuff

You'll need to occasionally update the app and celery containers, as well as migrate your database. For updating, `docker stack up -c docker-compose.yml flaskbb` will deal. 

For migrations, I've included that in the entrypoint but I've not tested it with automated options. For that, you'll need to ensure you'll have a connection to the target database and use `db-upgrade` as the entrypoint command. This could be included in the docker-compose file as a service that doesn't have a restart policy (see [this blog post](https://blog.alexellis.io/containers-on-swarm/) for more details).

There are also additional entry points that are potentially interesting for a user, I'll note *all of these run as root*, if you got access to the container in a way to execute arbitrary commands with it you'll get root access some how. (I researched how to get a bash script to drop privileges and didn't find any consistent advice other than to use `su` [which has issues of its own](https://jdebp.eu/FGA/dont-abuse-su-for-dropping-privileges.html))

* `flaskbb` this allows calling the flaskbb CLI and provides the config, so no need to remember to add `--config /var/run/flaskbb/flaskbb.cfg` every time, this passes all arguments and options down to the flaskbb command
* `python` this actually invokes the `flaskbb shell` command so you'll drop into a FlaskBB aware shell (which is probably what you want) -- if you install IPython, then that'll become the shell you use.
* `*` just a catch all to run arbitrary commands in the container except it automatically `exec`s the command

## Parting Notes

Figuring this out was a lot of fun, frustrating, but fun. In the process I learned more about docker networks, swarm, used configs and secrets for the first time and in general touched quite a bit of my personal infrastructure.

There are some things that you should know if you just blindly copy this into your own setup (hopefully you don't, but I'll point here if one of these bites you):

* The celery container runs as root but the workers drop their privileges to the flaskbb user. 
* The `useradd` command in the `Dockerfile.app` will also create a user on the machine that builds the container (sorry) but not the hosts that it runs on.

I will say I don't believe this setup is ready for heavy usage but my use case is testing deployments, migrations and features. I'll probably end up using some as a personal journal or something like that.

## Future Plans

There are somethings I'd like to add or extend in the future.

* Using Traefik to partition routing to the FlaskBB application, some directly to uWSGI and some to the nginx static assets server.
* Using rabbitmq as the celery broker. I'd like to play with rabbit more and this might be the motivating case to do that.
* Better logging -- I'm in the process of setting up an ELK stack on my network and have an [open PR on FlaskBB to improve logging](https://github.com/sh4nks/flaskbb/pull/327). Ideally, this will also include a statsd server that uwsgi will report to.
