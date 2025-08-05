# V1 Specs
## The goal
Have **CrowdSec SE** and a **bouncer of choice** (CloudFlare or Fastly) installed and running in an UpSun stack with only those **minimal actions** from the user:
*   Create a new upsun project and paste our config and scripts into it
*   Edit the .environment file to choose the bouncer (by providing the API key or something more secure like a secure store key in the appropriate env var for cloudflare OR/AND fastly)
*   Create an HTTP LOG integration (via [upsun UI or cli](https://docs.upsun.com/increase-observability/logs/forward-logs.html#forward-to-an-http-endpoint)) in any other projects they want to monitor with CrowdSec by just adding the URL to CrowdSec Project (obtained in upsun UI and that can be defined in config.yaml too)
## What it implies for out config and scripts:
### Have crowdsec installed and setup in a folder with access rights (working)
*   TODO **p1**: clean up scripts
*   TODO **p1**: Collection management
    *   **Install upsun collection**
        *   Side task, **create UpSuncollection**:
            *   parser s00 in repo: [01\_upsun-httplog.yaml](https://github.com/rr404/cs-upsun-experiment/blob/main/crowdsec/scripts/crowdsec/parsers/s00-raw/01_upsun-httplog.yaml)
            *   \+ Base HTTP
            *   \+ any additional things you find out are useful
    *   **Setup a cron for hub update/upgrade**
*   TODO **p2**: aliases to call cscli from anywhere
    *   at the moment we do it like so: _/app/cs/etc/crowdsec/cscli --config /app/cs/etc/crowdsec/config.yaml alerts list_
*   TODO **p2**: Clean upsun push process
    *   Find a way to NOT re-install every time if only minor things change (upon upsun push)
    *   We Can discuss optimal setup with upsun help techs
## Have chosen bouncer(s) setup automatically
*   At the moment I have done it by hand for Cloudflare to check it worked:
    *   Creating bouncer key
    *   Taking release and running config in a folder with access rights
    *   Checking it updates in cloudflare
*   TODO **p1**: if the environment variable for a bouncer is NOT EMPTY, install it
    *   **check**:
        *   Env var filled with necessary data TBD - CF API key for cloudflare
        *   Remediation scope in env
            *   default remediation (cscli, crowdsec), _lower impact for free with mention to empty to send all_
    *   **do**:
        *   install and config
        *   have system.d service copied and ran as user (same as for what's done for crowdsec)
## **Add Helpers**
*   TODO **p2**: Easy way to replay logs (via une interface web avec password)
    *   at least a doc to help them _upsun scp_ their logs to crowdsec project and then run a crowdsec DSN
*   TODO **p2: Easy Way to Enroll**
*   TODO **p3** We may use Web UI with passwords access rather than for user to go via SSH

### Misc and Security
*   TODO p1: find secure way to pass sensitive info like bouncer API keys
    *   Is .environment of project secure ?
    *   does upsun have a secure store ?
    *   For UI access where do we store the access password ? htaccess ? can we use upsun sso ?