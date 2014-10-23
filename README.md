# ![](https://raw.github.com/aptible/straptible/master/lib/straptible/rails/templates/public.api/icon-60px.png) Gentleman Jerry

![](https://quay.io/repository/aptible/gentlemanjerry/status?token=10d8074c-a102-46de-a3d1-869397b251ae)

Receives logs from [Joe Cool](https://github.com/aptible/joecool) instances, performs any filtering 
or mapping needed on the logs, and forwards them on to their final destination (syslog, 
ElasticSearch, etc.).

Gentleman Jerry is implemented as a [logstash](http://logstash.net) instance.

## Example

To run your own Gentleman Jerry, first create a self-signed certificate pair named 
jerry.key/jerry.crt:

```
$ mkdir /tmp/jerry-cert
$ openssl req -x509 -batch -nodes -days 3650 -newkey rsa:2048 -keyout /tmp/jerry-cert/jerry.key -out /tmp/jerry-cert/jerry.crt
```

Next, pull the image from quay (`docker pull quay.io/aptible/gentlemanjerry`) or build it locally
(`make build`). The image name will be `quay.io/aptible/gentlemanjerry:latest` if you pull or build
from the `master` branch.

Finally, start a container running that image that mounts in the certificate and key and runs on a 
port of your choice, say, 1234:

````
$ docker run -i -t -p 1234:5000 -v /tmp/jerry-cert:/tmp/certs quay.io/aptible/gentlemanjerry:latest
```

Logstash is written in JRuby; it may take several seconds to start up. You should see some output 
when it's ready.

Now you're ready to [spawn a Joe Cool](https://github.com/aptible/joecool#Example) and send logs 
to your instance.

## Environment variables

Runtime behavior of Joe Cool can be modified by passing the following environment variables to 
`docker run`:

* `LOGSTASH_OUTPUT_CONFIG`: A logstash output configuration. A 
  [full list of supported outputs](http://logstash.net/docs/1.4.2) includes syslog, elasticsearch, 
  files, and more. Gentleman Jerry includes the logstash contribs plugins package, so all outputs 
  should work out of the box. Default: `stdout { codec => rubydebug }`, which prints log messages 
  to stdout.

## Tests

All tests are implemented in bats. Run them with:

    make build

## Copyright

Copyright (c) 2014 [Aptible](https://www.aptible.com). All rights reserved.

[<img src="https://s.gravatar.com/avatar/c386daf18778552e0d2f2442fd82144d?s=60" style="border-radius: 50%;" alt="@aaw" />](https://github.com/aaw)
