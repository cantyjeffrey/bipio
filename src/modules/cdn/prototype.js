//Prototype.js

//Define default fs interactions
//Functionality in lib/cdn.js goes here

var fs = require('fs'),
	tldtools    = require('tldtools'),
	url = require('url'),
	fs = require('fs'),
	path = require('path'),
	http    = require('http'),
	https    = require('https'),
	temp = require('temp'),
	htmlparser = require('htmlparser2'),
	imagemagick = require('imagemagick');

// -----------------------------------------------------------------------------

var FileStorage = {

	fileHash : function(filePath, next) {
    // the file you want to get the hash
    var fd = fs.createReadStream(filePath);
    var hash = crypto.createHash('sha1');
    hash.setEncoding('hex');

    fd.on('end', function() {
        hash.end();
        next(false, hash.read())
    });

    fd.on('error', function(err) {
      next(err);
    });

    // read all file and pipe it (write it) to the hash object
    fd.pipe(hash);
  },

	httpSnarfResponseHandler : function(res, srcUrl, dstFile, next, hops) {
	    if (hops > 3) {
	    	next(true, 'too many redirects');
	    }
	    else if (res.headers['content-length'] == 0) {
	    	var msg = 'Zero Size Reply';
	    	console.log(msg);
	    	next(true, msg);
	    }
	    else if (res.statusCode == 200) {
	    	var outFile = fs.createWriteStream(dstFile);
	    	res.pipe(outFile);
	    	outFile.on('close', function() {
	    		next(false, {
	    			'url' : srcUrl,
	    			'file' : dstFile
	    		});
	    	}).on('error', function(e) {
	    		next(true, e);
	    		console.log(e);
	    	});
	    }
	    else if (res.statusCode == 301) {
	    	srcUrl = res.headers.location;
	    	hops++;
	    	this.httpFileSnarf(srcUrl, dstFile, next, hops);
	    }
	    else {
	    	next(true, res);
		}
	},

	/**
	* Given a http(s) url, retrieves a file, follows 301's etc. and
	* streams to dstFile
	*/
	httpFileSnarf : function(srcUrl, dstFile, next, hops) {
	    var urlTokens = tldtools.extract(srcUrl),
	    self = this,
	    proto = urlTokens.url_tokens.protocol;

	    if (undefined === hops) {
	      hops = 1;
	    }

	    if (proto == 'http:') {
	      http.get(srcUrl, function(res) {
	        self.httpSnarfResponseHandler(res, srcUrl, dstFile, next, hops);
	      }).on('error', function(e) {
	        console.log(e);
	        next(true, e);
	      });
	    } else if (proto == 'https:') {
	      https.get(srcUrl, function(res) {
	        self.httpSnarfResponseHandler(res, srcUrl, dstFile, next, hops);
	      }).on('error', function(e) {
	        console.log(e);
	        next(true, e);
	      });
	    } else {
	      next(true, 'Bad Protocol : ' + proto);
	    }
	},

	  /**
	     * Given a file creation strategy we know about, takes the meta data payload
	     * and renormalizes it for internal use
	     *
	     */
	normedMeta: function(strategy, txId, payload) {
	    var normFiles = [],
	    struct, f;
	    if (strategy == 'express') {
	      for (file in payload) {
	        f = payload[file];
	        struct = {
	          txId : txId,
	          size : f.size,
	          localpath : f.path,
	          name : f.originalname,
	          //type : f.headers['content-type'],
	          type : f.mimetype,
	          encoding : 'binary' // @todo may not be binary, express bodyparser looks broken after 3.4.0
	        //encoding : f._writeStream.encoding

	        }
	        normFiles.push(struct);
	      }
	    } else if (strategy == 'haraka') {
	      normFiles = payload;
	      normFiles.txId = txId;
	    } else {
	      normFiles = payload;
	    }

	    return normFiles;
	},


  /**
     * Creates a temporary file based on an incoming readStream
     *
     * @param inStream ReadStream
     */
	tmpStream : function(inStream, prefix, contentType, fileName, cb) {
	    if (undefined == prefix) {
	      prefix = 'tmp';
	    }
	    prefix += '-';

	    var writeStream = temp.createWriteStream({
	      prefix : prefix
	    });
	    fs.chmod(writeStream.path, 0644);
	    inStream.pipe(writeStream);
	    inStream.resume();
	    writeStream.on('close', function(err) {
	      if (!err && cb) {

	        cb(false, writeStream.path, contentType, fileName, {
	          size : writeStream.bytesWritten
	        });
	      }
	    });

	    return writeStream.path;
	},

	convert : function(args, next) {
		imagemagick.convert(args, next);
	},

	resize : function(args, next) {
		imagemagick.resize(args, next);
	},

	_favicoHandler : function(res, host, next) {
		var favUrl = null;

	    if (res.headers.link && /rel=icon/.test(res.headers.link) ) {
	      favUrl = res.headers.link.replace(/<|>.*$/g, '');
	    }

	    var p = new htmlparser.Parser({
	      onopentag : function(name, attrs) {
	        if ('link' === name) {
	          if (attrs.href && /icon/.test(attrs.rel)) {
	            favUrl = attrs.href;
	          }
	        }
	      }
	    });

	    var body = '';
	    res.on('data', function (chunk) {
	      if (!favUrl) {
	        p.write(chunk);
	      }
	    });

	    res.on('end', function() {
	      var suffix, hashFile;
	      if (favUrl) {
	        suffix = '.' + favUrl.split('.').pop().replace(/\?.*$/, '');
	        hashFile = app.helper.strHash(host) + suffix
	      }

	      p.end();
	      next(favUrl, suffix, hashFile);
	    });
	},

	  // retrieves the favicon for a site url
	getFavicon : function(url, next) {
	    var self = this,
	      tokens = app.helper.tldtools.extract(url),
	      host = tokens.url_tokens.protocol + '//' + tokens.url_tokens.host,
	      cdnPath = 'icofactory',
	      fileSuffix = '.ico',
	      favUrl = host + '/favicon' + fileSuffix;

	    var hashFile = app.helper.strHash(host) + fileSuffix,
	      dDir = DATA_DIR + '/cdn/img/' + cdnPath + '/',
	      filePath = dDir + hashFile,
	      cdnUri = CFG.cdn_public + '/' + cdnPath + '/' + hashFile;

	    self.httpFileSnarf(favUrl, filePath, function(err, res) {
	      // try parsing html for link
	      if (err) {
	        if ('http:' === tokens.url_tokens.protocol) {
	          http.get(host, function(res) {
	           self._favicoHandler(res, host, function(favUrl, suffix, hashFile) {
	             if (favUrl) {
	               filePath = dDir + hashFile;
	               cdnUri = CFG.cdn_public + '/' + cdnPath + '/' + hashFile;
	               self.httpFileSnarf(favUrl, filePath, function(err, resp) {
	                 next(err, cdnUri);
	               });
	             } else {
	               next(false, null);
	             }
	           });
	          }).on('error', function(e) {
	            console.log(e);
	            next(true, e);
	          });

	        } else if ('https:' === tokens.url_tokens.protocol) {
	          https.get(host, function(res) {
	           self._favicoHandler(res, host, function(favUrl, suffix, hashFile) {
	             if (favUrl) {
	               filePath = dDir + hashFile;
	               cdnUri = CFG.cdn_public + '/' + cdnPath + '/' + hashFile;
	               self.httpFileSnarf(favUrl, filePath, function(err, resp) {
	                 next(err, cdnUri);
	               });
	             } else {
	               next(false, null);
	             }
	           });
	          }).on('error', function(e) {
	            console.log(e);
	            next(true, e);
	          });
	        }
	      } else {
	        next(false, cdnUri);
	      }
	    });
	},

	httpStream: function(url, outFile, cb, exports, fileStruct) {
		outLock = outFile + '.lock';

		fs.exists(outLock, function(exists) {
			if (exists) {
				app.logmessage(' LOCKED, skipping [' + outFile + ']');
			}
			else {
				app.logmessage(' writing to [' + outFile + ']');
				fs.exists(outFile, function(exists) {
					if (exists) {
						fs.stat(outFile, function(err, stats) {
							if (err) {
								app.logmessage(err, 'error');
								next(true);
							}
							else {
								app.logmessage(' CACHED, skipping [' + outFile + ']');
								fileStruct.size = stats.size;
								cb(false, exports, fileStruct);
							}
						});
					}
					else {
						fs.open(outLock, 'w', function() {
							app.logmessage(' FETCH [' + url + '] > [' + outFile + ']');
							request.get(url, function(exports, fileStruct) {
								return function(error, res, body) {
									fs.unlink(outLock);
									if (!error && res.statusCode == 200) {
										fs.stat(outFile, function(err, stats) {
											if (err) {
												app.logmessage(err, 'error');
												next(true);
											}
											else {
												app.logmessage(' done [' + outFile + ']');
												fileStruct.size = stats.size;
												cb(false, exports, fileStruct);
											}
										});
									}
								}
							}(exports, fileStruct)).pipe(fs.createWriteStream(outFile));
						});
					}
				});
			}
		});
	}
};

module.exports = FileStorage;
