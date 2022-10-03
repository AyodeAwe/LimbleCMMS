restify = require("restify");
const server = restify.createServer({
    name: 'LimbleCMMS',
    version: '1.0.0'
  });

server.use(restify.plugins.acceptParser(server.acceptable));
server.use(restify.plugins.queryParser());
server.use(restify.plugins.bodyParser());

server.get('/', function (req, res, next) {
  res.send("Welcome to LimbleCMMS");
  return next();
});

server.listen(80, function () {
  console.log('%s listening at %s', server.name, server.url);
});