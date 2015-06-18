# ![](https://raw.github.com/aptible/straptible/master/lib/straptible/rails/templates/public.api/icon-60px.png) Gentleman Jerry

![](https://quay.io/repository/aptible/gentlemanjerry/status?token=10d8074c-a102-46de-a3d1-869397b251ae)

Receives logs from [Joe Cool](https://github.com/aptible/joecool) instances, performs any filtering
or mapping needed on the logs, and forwards them on to their final destination (syslog,
ElasticSearch, etc.).

Gentleman Jerry is implemented as a [logstash](http://logstash.net) instance.

## Example

To run your own Gentleman Jerry, first create a key and self-signed certificate named
jerry.key/jerry.crt. Logstash and logstash-forwarder require either the certificate common
name to match the domain used to address GentlemanJerry or that the server IP is
specified as the Subject Alternative Name in the certificate. In the instructions that
follow, we'll assume the latter and describe the process for IP-based addressing.

First, make a `/tmp/jerry-cert` directory and create a config file named `/tmp/jerry-cert/jerry.config`
with the following contents (substituting the actual server IP for `$IP_ADDRESS` or using
the address of the `docker0` interface `$IP_ADDRESS` if you're going to run everything locally).

```
[req]
distinguished_name = req_distinguished_name
x509_extensions = v3_req
prompt = no
[req_distinguished_name]
CN = $IP_ADDRESS
[v3_req]
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer
basicConstraints = CA:TRUE
subjectAltName = IP:$IP_ADDRESS
```

Next, use that config file to generate the key and self-signed certificate:

```
$ openssl req -x509 -batch -nodes -days 3650 -newkey rsa:2048 -config /tmp/jerry-cert/jerry.config -keyout /tmp/jerry-cert/jerry.key -out /tmp/jerry-cert/jerry.crt
```

Pull the image from quay (`docker pull quay.io/aptible/gentlemanjerry`) or build it locally
(`make build`). The image name will be `quay.io/aptible/gentlemanjerry:latest` if you pull or build
from the `master` branch.

Finally, start a container running that image that mounts in the certificate and key and runs on a
port of your choice, say, 1234:

````
$ docker run -i -t -p 1234:5000 -v /tmp/jerry-cert:/tmp/certs quay.io/aptible/gentlemanjerry:latest
```

Logstash is written in JRuby; it may take several seconds to start up. You should see the message
"Logstash startup completed" when it's up and running.

Now you're ready to [spawn a Joe Cool](https://github.com/aptible/joecool#Example) and send logs
to your instance.

## Environment variables

Runtime behavior of Gentleman Jerry can be modified by passing the following environment variables to
`docker run`:

* `LOGSTASH_OUTPUT_CONFIG`: A logstash output configuration. A
  [full list of supported outputs](https://www.elastic.co/guide/en/logstash/current/output-plugins.html)
  includes syslog, elasticsearch, files, and more. Gentleman Jerry includes the syslog output as
  well as many other common outputs that ship with Logstash. See `/logstash-1.5.0/Gemfile` in the
  Gentleman Jerry image to see a full list of available outputs. Default: `stdout { codec => rubydebug }`,
  which prints log messages to stdout.
* `LOGSTASH_FILTERS`: Any additional logstash filter definitions. Example: to rename the `log`
  field to `message`, set this variable to "filter { mutate { rename => ['log', 'message'] } }".
  Default: empty string.
* `LOGSTASH_MAX_HEAP_SIZE`: Optional. Restricts the JVM max heap size for the logstash agent.
  Default is "64M".

## Tests

All tests are implemented in bats. Run them with:

    make build

## Copyright

Copyright (c) 2014 [Aptible](https://www.aptible.com). All rights reserved.

[<img src="https://s.gravatar.com/avatar/c386daf18778552e0d2f2442fd82144d?s=60" style="border-radius: 50%;" alt="@aaw" />](https://github.com/aaw)
