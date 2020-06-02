## wonderfall/mastodon

A GNU Social-compatible microblogging server : https://github.com/tootsuite/mastodon

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
