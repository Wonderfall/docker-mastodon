## wonderfall/mastodon

A GNU Social-compatible microblogging server : https://github.com/tootsuite/mastodon

___

⚠️**DEPRECIATED**: don't worry, I'll keep maintaing it for a while. This image was made years ago and needs some rework:
- For instance it uses `su-exec` to degrade privileges, which is fine as an attempt to get a *rootless running* image, but more secure ways to make sure *root* is never used should be preferred.
- As a consequence to that, a newer image should drop all the `chown` instructions at startup time: no more seconds of waiting, even minutes if you're using overlayfs as the storage driver (which is Docker's default). This was fine for flexibility, but users should really learn how to manage the permissions of their volumes.
- It's a pain to maintain, since Mastodon is a very bloated software full of features but also full of dependencies. The streaming server wasn't properly working on 3.3.0 due to an incompatible node.js version.

As I said, I'll keep "maintaing" it for now (I always though of my images as being bases for you own images, really don't run Docker images from random dudes like me from the Internet), but I'll eventually make a brand new image sometime soon. Meaning, you should be prepared to maintain or make your own image, or use the "official one" *(which I'm not a fan of)*. Above all, take care and take security seriously.

___

**Note (Apr. 2021)**: currently Mastodon "stable" can't be built beacause of some [yanked packages](https://github.com/tootsuite/mastodon/issues/15986). Not only that, but the streaming component refuses to work correctly with node v14. This is fixed in main.

#### Why this image?
This image is not the official one. The main difference you can notice is that all processes (web, streaming, sidekiq) are running in a single container, thanks to s6 (a supervision suite). Therefore it's easier to deploy, but not recommended for scaling.

#### Features
- Based on Alpine Linux.
- As lightweight as possible.
- All-in-one container (s6).
- Assets are precompiled.
- No root processes.

#### Build-time variables
- **VERSION** : version of Mastodon *(default : latest version)*
- **REPOSITORY** : location of the code *(default : tootsuite/mastodon)*

#### Environment variables you should change
- **UID** : mastodon user id *(default : 991)*
- **GID** : mastodon group id *(default : 991)*
- **RUN_DB_MIGRATIONS** : run database migrations at startup *(default : true)*
- **SIDEKIQ_WORKERS** :  number of Sidekiq workers *(default : 5)*
- Other environment variables : https://github.com/tootsuite/mastodon/blob/master/.env.production.sample

#### Volumes
- **/mastodon/public/system** : Mastodon files
- **/mastodon/log** : Mastodon logfiles (mount if you prefer to)

#### Ports
- **3000** : web
- **4000** : streaming
