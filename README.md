# Seerr Anime Request Router/Fixer

This is a quickly vibecoded bash script run on an interval to fix when you have an individual anime Sonarr/Radarr instance and want requested media to be routed accordingly automatically. The most common usecase of this is when you follow Trash Guides and end up creating HD, 4K, and anime Sonarr/Radarr instances. Seerr only has built-in routing for 4K and non-4K, but not anime. This aims to fix that without trusting users to manually select the correct instance. I hope Seerr will implement anime routing soon. In the meantime, this is here.

When a user requests an anime or show, this script will correct the request to be set to the according instance both ways. So if a user sets an anime to your non-anime instance, it will correct it. Likewise, if a user sets a non-anime to your anime instance, it will correct it. It will also auto-reject all 4K anime requests as anime is rarely released in 4K natively.

## Setup With Docker

1. Add your Sonarr/Radarr instances to Seerr
2. Disable autoapprove in Seerr. This script can auto approve for you after fixing things. The setting for this script is global and not user-scoped for auto approval and applies to all media requests
3. Get your Seerr API key and set the environment variable
4. Visit http://YOUR_SEERR_INSTANCE/api/v1/service/radarr and http://YOUR_SEERR_INSTANCE/api/v1/service/sonarr to get your Sonarr and Radarr server IDs and set the environment variables accordingly.
5. Set other environment variables accordingly as listed in the compose.yaml example

## Non-Docker

You can use cron or any scheduler with script.sh and set env variables, however Docker is recommended. 
