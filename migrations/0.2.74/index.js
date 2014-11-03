var fs = require('fs'),
	Migration = {
    run : function(app, configPath, next) {
    	var config = JSON.parse(fs.readFileSync(configPath));
		if (!config.cdn.hasOwnProperty(localPath) && typeof config.cdn === 'string') {
			console.info('Re-writing CDN config path');
        	config.cdn = {
        		localPath: config.cdn
        	}
        	fs.writeFile(configPath , JSON.stringify(config, null, 2), function(err) {
		        if (err) {
		            next(err, 'error');
		        } else {
		            console.info("\nConfig written to : " + configPath + "\n");
		            next();
		        }
        	});
		}
	}
}

module.exports = Migration;