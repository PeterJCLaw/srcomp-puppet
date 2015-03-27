var mainWebsite = 'https://srobo.mooo.com';

var http = require('http');
var request = require('request');

addWatcher('compbox stream', function(ack, err) {
    var req = http.request({'hostname': 'localhost',
                            'path': '/stream'}, function(res) {
        if (res.statusCode !== 200) {
            err(res.statusCode);
        } else if (res.headers['content-type'] !== 'text/event-stream') {
            err("Bad content type: " + res.headers['content-type']);
        } else {
            req.abort();
            ack();
        }
    });

    req.on('error', function(e) {
        err(e.message);
    });
    req.end();
});

addWatcher('compbox API', watchHTTP('http://localhost/comp-api/arenas'));

addWatcher('upstream API', watchHTTP(mainWebsite + '/comp-api/arenas'));

addWatcher('upstream sync', function(ack, err) {
    request('http://localhost/comp-api/state', function(e, response, body) {
        if (e) {
            err("downstream " + e.message);
        } else if (response.statusCode != 200) {
            err("downstream " + response.statusCode);
        } else {
            var dsState = JSON.parse(body).state;
            request(mainWebsite + '/comp-api/state', function(e, response, body) {
                if (e) {
                    err("upstream " + e.message);
                } else if (response.statusCode != 200) {
                    err("upstream " + response.statusCode);
                } else {
                    var usState = JSON.parse(body).state;
                    if (dsState === usState) {
                        ack();
                    } else {
                        err("DESYNC: upstream " + usState.substr(0, 7) + " " +
                            "downstream " + dsState.substr(0, 7));
                    }
                }
            });
        }
    });
});

addWatcher('IDE', watchHTTP(mainWebsite + '/ide/control.php/info/about'));
