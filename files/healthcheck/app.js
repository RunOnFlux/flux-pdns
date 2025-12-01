var express = require('express');
var path = require('path');
var cookieParser = require('cookie-parser');
var logger = require('morgan');

var healthRouter = require('./routes/health-simple.js');
var healthDetailRouter = require('./routes/healthdetail.js');

var app = express();

app.use(express.json());
app.use(express.urlencoded({ extended: false }));
app.use(cookieParser());

app.use('/health', healthRouter);
app.use('/healthdetail', healthDetailRouter);

module.exports = app;
