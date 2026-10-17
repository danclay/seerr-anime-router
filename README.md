# Seerr Anime Request Fixer/Router

This is a quickly vibecoded script run on an interval to fix when you have an individual anime Sonarr/Radarr instance and want requested media to be routed accordingly automatically.

## Setup

1. Add your Sonarr/Radarr instances to Seerr
2. Disable autoapprove in Seerr. This script can auto approve for you after fixing things. The setting for this script is global and not user-scoped for auto approval and applies to all media requests
3. Get your Seerr API key and set the environment variable
4. Visit http://YOUR_SEERR_INSTANCE/api/v1/service/radarr and http://YOUR_SEERR_INSTANCE/api/v1/service/sonarr to get your Sonarr and Radarr server IDs and set the environment variables accordingly.
5. Set other environment variables accordingly as listed in the compose.yaml example