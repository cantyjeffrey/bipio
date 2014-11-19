var RackspaceProto = require('./src/rackspace.js');
var FsProto = require('./src/fs.js');

function Fs_Cdn(options) {
	if (options && options.hasOwnProperty("provider")) {
		console.log("fs-cdn initialized in REMOTE mode. Provider: " + options.provider);
		switch(options.provider) {
			case "rackspace":
				this.prototype = RackspaceProto.prototype;
				return new RackspaceProto(options);
		};
	}
	else {
		console.log("fs-cdn initialized in LOCAL mode.");
		this.prototype = FsProto.prototype;
		return new FsProto();
	}
};

module.exports = Fs_Cdn;