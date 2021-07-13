requirejs([
    'jquery',
    'base/js/utils',
], function($, utils
    ){
    utils.change_favicon("custom/favicon.ico")

	var uuid = "";
	$('<span class="save_widget">Time left:&nbsp;<span id="timer" class="checkpoint_status"></span></span>').insertAfter(jQuery("#ipython_notebook"));
	$.getJSON( "https://ms-backend-api.mdscdev.com/api/1.0/rents/service/status/" + uuid, function( data ) {
	  var countDownDate = new Date().getTime() + data.result.timeToEnd * 1000;
	  var x = setInterval(function() {
	    var now = new Date().getTime();
	    var distance = countDownDate - now;
	    var minutes = Math.floor((distance % (1000 * 60 * 60)) / (1000 * 60));
	    var seconds = Math.floor((distance % (1000 * 60)) / 1000);
	    document.getElementById("timer").innerHTML = minutes + "m " + seconds + "s ";

	    if (distance < 0) {
	      clearInterval(x);
	      document.getElementById("timer").innerHTML = "EXPIRED";
	      //location.reload();
	    }
	  }, 1000);
	});
});
