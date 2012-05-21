/*
   Shellcast
   =========
*/

var Shellcast = function (params) {
	var self = this;

	// Parameter validation and defaults
	if (params === undefined)
		params = {};
	if (params.url === undefined)
		throw "Shellcast requires you pass a url";
	if (params.element === undefined)
		throw "Shellcast requires you pass an element";
	if (params.terminal_character_width === undefined)
		params.terminal_character_width = 8; // Menlo 0.8em or 0.9em
	if (params.autoplay === undefined)
		params.autoplay = true;

	self.params = params;
	self.element = params.element;

	// Fetch the URL
	$.ajax({
		url: params.url,
		dataType: 'json',
		success: function (data) {
			self.loadData(data);
		}
	});
}

Shellcast.ascii_table_map = {
	8:   "\u2190BSP",
	9:   "\u21e5", // tab
	10:  "\u21a9", // new line
	11:  "\u21e5", // tab
	13:  "\u21a9", // new line
	27:  'ESC',
	32:  "&nbsp;", // space
	127: "\u2190DEL",
};

Shellcast.control_code_map = {
	"\x1b[B": "\u2193", // down arrow
	"\x1bOB": "\u2193",
	"\x1b[C": "\u2192", // right arrow
	"\x1bOC": "\u2192",
	"\x1b[A": "\u2191", // up arrow
	"\x1bOA": "\u2191",
	"\x1b[D": "\u2190", // left arrow
	"\x1bOD": "\u2190"
};

Shellcast.prototype.loadData = function (data) {
	var self = this;
	self.data = data;

	self.element.toggleClass('shellcast', true);

	// Create the terminal
	var term = new Terminal(
		data.term_cols,
		data.term_rows
	);

	// Create Terminal DOM, attach it to the element and set its width
	var terminal = $( term.open() );
	self.terminalWrapper = $('<div class="terminal-wrapper"></div>').append(terminal);
	self.element.append(self.terminalWrapper);
	terminal.width( self.params.terminal_character_width * data.term_cols );

	var captureMouseEvents = $('<div class="capture-mouse-events"></div>');
	self.terminalWrapper.append(captureMouseEvents);
	captureMouseEvents.hover(
		$.proxy( self.hoverIn, self ),
		$.proxy( self.hoverOut, self )
	);
	captureMouseEvents.click( $.proxy( self.click, self ) );

	// Create a place to display input
	self.inputDisplayDiv = $('<div class="input-display"></div>');
	self.element.append(self.inputDisplayDiv);
	self.inputDisplayDiv.width( self.params.terminal_character_width * data.term_cols );

	// Create a new player, give it the term and hit play
	self.player = new Shellcast.Player(term);
	self.player.load(data);

	self.player.onStateChange = $.proxy( self.updateHover, self );
	self.player.onInputKey = $.proxy( self.addInputKey, self );

	if (self.params.autoplay)
		self.player.play();
}

Shellcast.prototype.addInputKey = function (key) {
	var self = this;
	// Map the key to something a bit more readable for non-visible characters

	var text = key;
	if (Shellcast.control_code_map[key])
		text = Shellcast.control_code_map[key];
	else if (key.length === 1) {
		var ord = key.charCodeAt(0);
		if (Shellcast.ascii_table_map[ord])
			text = Shellcast.ascii_table_map[ord];
		else if (ord <= 31)
			text = 'Ctrl-' + String.fromCharCode(ord + 64);
	}

	var kbd = $('<kbd class="light">' + text + '</kbd>');
	self.inputDisplayDiv.prepend(kbd);

	// Add margin-left padding to space out keys that were typed after a delay
	var now = new Date().valueOf();
	if (self.lastAddInputKey === undefined)
		self.lastAddInputKey = now;
	var elapsed = now - self.lastAddInputKey;
	self.lastAddInputKey = now;
	kbd.css('margin-left', Math.floor(elapsed / 50) + 'px');

	// Remove the keys after some time elapses
	window.setTimeout(function () { kbd.remove() }, 10000);
}

Shellcast.prototype.hoverIn = function () {
	var self = this;
	if (self.hoverDiv !== undefined)
		return;
	
	// Create a hover div which will display an action that the user can
	// perform if they click.  Position it in the center of the terminal

	self.hoverDiv = $('<div class="action-cover"></div>');
	self.updateHover( self.player.state );
	self.terminalWrapper.prepend( self.hoverDiv );

	self.hoverDiv.css('top',
		(
		 	self.terminalWrapper.height() / 2 -
			self.hoverDiv.height() / 2
		) + 'px'
	);
}

Shellcast.prototype.hoverOut = function () {
	this.hoverDiv.remove();
	this.hoverDiv = undefined;
}

Shellcast.prototype.click = function () {
	var self = this;
	if (self.player.playing)
		self.player.pause();
	else if (self.player.paused)
		self.player.unpause();
	else
		self.player.play();
}

Shellcast.prototype.updateHover = function (state) {
	var self = this;

	// Display the 'replay' message after the movie stops
	if (state === 'stopped')
		self.hoverIn();

	if (! self.hoverDiv)
		return;
	var action;
	if (state === 'playing')
		action = 'pause';
	else if (state === 'paused')
		action = 'unpause';
	else if (state === 'stopped')
		action = 'replay';
	else 
		action = 'play';
	self.hoverDiv.html(action);
}

/*
   Shellcast Player
   ================
*/

Shellcast.Player = function (term) {
	this.term = term;
	this.state = undefined;
	this.playing = false;
	this.paused  = false;
	this.reachedLastFrame = false
	this.onStateChange = undefined;
	this.onInputKey    = undefined;
}

Shellcast.Player.prototype.load = function (data) {
	this.data = data;
}

Shellcast.Player.prototype.play = function () {
	var player = this;

	if (player.playing)
		return;

	player.stateChange('playing');

	if (player.reachedLastFrame) {
		// Reset the terminal
		player.reachedLastFrame = false;
		player.term.reset();
	}

	player.currentFrame = -1;
	player.playNextFrame();
}

Shellcast.Player.prototype.pause = function () {
	var player = this;
	if (player.paused)
		return;
	player.stateChange('paused');
	if (player.nextFrameTimeoutHandle) {
		window.clearTimeout(player.nextFrameTimeoutHandle);
		player.nextFrameTimeoutHandler = undefined;
	}
}

Shellcast.Player.prototype.unpause = function () {
	var player = this;
	if (! player.paused)
		return;
	player.stateChange('playing');
	player.playNextFrame();
}

Shellcast.Player.prototype.reset = function () {
	var player = this;
	if (player.playing)
		player.pause;
	player.reachedLastFrame = true;
	player.play();
}

Shellcast.Player.prototype.stateChange = function (state) {
	var player = this;
	player.state = state;

	if (state === 'playing') {
		player.playing = true;
		player.paused  = false;
		player.term.startBlink();
	}
	else if (state === 'stopped') {
		player.reachedLastFrame = true;
		player.playing = false;
		player.term.stopBlink();
	}
	else if (state === 'paused') {
		player.playing = false;
		player.paused  = true;
		player.term.stopBlink();
	}

	if (player.onStateChange)
		player.onStateChange(state);
}

Shellcast.Player.prototype.playNextFrame = function () {
	var player = this;

	// Check to see if the next frame exists
	if (player.currentFrame + 1 > player.data.frames.length - 1) {
		player.stateChange('stopped');
		return;
	}

	// Fetch the next frame and ensure it's of the proper type
	player.currentFrame = player.currentFrame + 1;

	var frame = player.data.frames[ player.currentFrame ];
	if (frame === undefined) {
		console.error("Frame " + player.currentFrame + " doesn't exist");
		return;
	}
	if (! $.isArray(frame) || frame.length !== 3) {
		console.error("Frame " + player.currentFrame + " is not an array with three items", frame);
		return;
	}

	// Act upon the frame contents
	if (frame[0] === 'in' && player.onInputKey) {
		player.onInputKey(frame[2]);
	}
	else if (frame[0] === 'out') {
		player.term.write(frame[2]);
	}
	else {
		console.error("Frame " + player.currentFrame + " has unsupported type", frame);
		return;
	}

	// Set timeout for the next frame.  The timer value for this frame represents the number of
	// ms until this frame was displayed, so need to look ahead for this.
	var timeout = 0;
	if (player.currentFrame < player.data.frames.length - 1)
		timeout = player.data.frames[ player.currentFrame + 1 ][1];
	player.nextFrameTimeoutHandle = window.setTimeout(
		function () { player.playNextFrame() },
		timeout
	);
}
