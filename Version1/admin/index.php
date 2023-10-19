<!DOCTYPE html>
<html><head><meta http-equiv="Content-Type" content="text/html; charset=UTF-8">
<title>Meek Admin</title>
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
body {
    position: relative;
    margin: 0 auto;
    background: #fff;
    font-family: Verdana,Arial,Helvetica,sans-serif;
    font-size: 12px;
    color: #333;
}

h1 {
width: 100%;
  padding: 12px;
  border: 1px solid #ccc;
  border-radius: 4px;
  box-sizing: border-box;
  margin-top: 6px;
  margin-bottom: 16px;
  background-color: #008CBA;
  color: white;
  text-align: center;
}

.Button {
  background-color: white;
  color: black;
  border: 2px solid #008CBA;
  padding: 8px 12px;
  margin: 4px 2px;
  transition-duration: 0.4s;
  width: 100%;
}

.ButtonA {
  background-color: white;
  color: black;
  border: 2px solid #008CBA;
}

.ButtonA:hover {
  background-color: #008CBA;
  color: white;
  box-shadow: 0 12px 16px 0 rgba(0,0,0,0.24), 0 17px 50px 0 rgba(0,0,0,0.19);
}

input:required:invalid, input:focus:invalid, textarea:required:invalid, textarea:focus:invalid {
    background-image: url(data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAwAAAAMCAYAAABWdVznAAAAGXRFWHRTb2Z0d2FyZQBBZG9iZSBJbWFnZVJlYWR5ccllPAAAAT1JREFUeNpi/P//PwMpgImBRMACY/x7/uDX39sXt/67cMoDyOVgMjBjYFbV/8kkqcCBrIER5KS/967s+rmkXxzI5wJiRSBm/v8P7NTfHHFFl5mVdIzhGv4+u///x+xmuAlcdXPB9KeqeLgYd3bDU2ZpRRmwH4DOeAI07QXIRKipYPD35184/nn17CO4p/+cOfjl76+/X4GYAYThGn7/g+Mfh/ZZwjUA/aABpJVhpv6+dQUjZP78Z0YEK7OezS2gwltg64GmfTu6i+HL+mUMP34wgvGvL78ZOEysf8M1sGgZvQIqfA1SDAL8iUUMPIFRQLf+AmMQ4DQ0vYYSrL9vXDz2sq9LFsiX4dLRA0t8OX0SHKzi5bXf2HUMBVA0gN356N7p7xdOS3w5fAgcfNxWtn+BJi9gVVBOQfYPQIABABvRq3BwGT3OAAAAAElFTkSuQmCC);
    background-position: right top;
    background-repeat: no-repeat;
    box-shadow: none;
}

fieldset input, fieldset textarea, fieldset select {
    padding: 2px 4px;
    border: 1px solid #ccc;
    border-radius: 2px;
    background: #fff;
    line-height: 1.1;
    font-family: inherit;
    font-size: 1.1em;
}

fieldset {
    border: 2px solid #e0d8b7;
    background: #fcfaf0;
    color: #000;
}

input:required:valid, textarea:required:valid {
    background-image: url(data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAwAAAAMCAYAAABWdVznAAAAGXRFWHRTb2Z0d2FyZQBBZG9iZSBJbWFnZVJlYWR5ccllPAAAAZZJREFUeNpi/P//PwMpgImBRMAy58QshrNPTzP8+vOLIUInisFQyYjhz98/DB9/fmT48/+35v7H+8KNhE2+WclZd+G0gZmJmYGThUNz1fUVMZtvbWT59eUXG9wGZIWMUPj993eJ5VeWxuy8veM/CzPL3yfvH/9H0QBSBDYZyOVm4mGYfn6q4cory5lYmFh+MrEwM/76/YsR7mk2ZjbWP///WP37/y8cqIDhx58fjvtu7XV6//ndT34G/v8FasUsDjKO/+A2PP3wpGLd+TVsfOz8XH6KAT+nHpokcu7h6d9q/BoMxToVbBYqlt9///+1GO4/WVdpXqY/zMqXn13/+vTjI9mj94/y//v9/3e9ZRObvYbDT0Y2xnm///x+wsfHB3GSGLf41jb3rv0O8nbcR66d+HPvxf2/+YZFTHaqjl8YWBnm/vv37yly5LL8+vuLgYuVa3uf/4T/Kd8SnSTZpb6FGUXwcvJxbAPKP2VkZESNOBDx8+9PBm4OwR1TwmYwcfzjsBUQFLjOxs52A2YyKysrXANAgAEA7buhysQuIREAAAAASUVORK5CYII=);
    background-position: right top;
    background-repeat: no-repeat;
}

input {
  width: 100%;
  padding: 12px;
  border: 1px solid #ccc;
  border-radius: 4px;
  box-sizing: border-box;
  margin-top: 6px;
  margin-bottom: 16px;
}

input[type=submit] {
background-color: white;
  color: black;
  border: 2px solid #008CBA;
  padding: 8px 12px;
  margin: 4px 2px;
  transition-duration: 0.4s;
  width: 100%;
}

.container {
  background-color: #f1f1f1;
  padding: 20px;
}

#message {
  display:none;
  background: #f1f1f1;
  color: #000;
  position: relative;
  padding: 20px;
  margin-top: 10px;
}

#message p {
  padding: 10px 35px;
  font-size: 18px;
}

.valid {
  color: green;
}

.valid:before {
  position: relative;
  left: -5px;
  content: "   ^|^t";
}

.invalid {
  color: red;
}

.invalid:before {
  position: relative;
  left: -5px;
  content: "   ^|^v";
}

.grid-container {
  --grid-layout-gap: 10px;
  --grid-column-count: 3;
  --grid-item--min-width: 100px;
  --gap-count: calc(var(--grid-column-count) - 1);
  --total-gap-width: calc(var(--gap-count) * var(--grid-layout-gap));
  --grid-item--max-width: calc((100% - var(--total-gap-width)) / var(--grid-column-count));
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(max(var(--grid-item--min-width), var(--grid-item--max-width)), 1fr));
  grid-gap: var(--grid-layout-gap);
}

.grid-container2 {
  --grid-layout-gap: 10px;
  --grid-column-count: 2;
  --grid-item--min-width: 100px;
  --gap-count: calc(var(--grid-column-count) - 1);
  --total-gap-width: calc(var(--gap-count) * var(--grid-layout-gap));
  --grid-item--max-width: calc((100% - var(--total-gap-width)) / var(--grid-column-count));
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(max(var(--grid-item--min-width), var(--grid-item--max-width)), 1fr));
  grid-gap: var(--grid-layout-gap);
}

p {
  border-bottom: 2px solid red;
}

button {
  background: none;
  border: none;
  padding: 1em 1.5em;
  font-size: .875rem;
  color: #636269;
  font-family: inherit;
  background-color: #e0e5ec;
  cursor: pointer;
  &:hover {
    background-color: darken(#e0e5ec, 2%);
  }
}

</style>
</head>
<body>
<p><b>Software section</b></p>
<div class="grid-container">
        <form method="post">
        <div class="grid-item">
                <h1>System</h1>
                <div class="grid-container">
                        <button type="submit" class="Button ButtonA" name="Meek" value="System-Reboot">
                        <i class="fas fa-power-off"></i>
                        Reboot
                        </button>

                        <button type="submit" class="Button ButtonA" name="Meek" value="System-Update">
                        <i class="fa-solid fa-wrench"></i>
                        Update
                        </button>
                </div>

        </div></form>

        <form method="post">
        <div class="grid-item">
                <h1>Zigbee</h1>
                <div class="grid-container">
                        <button type="submit" class="Button ButtonA" name="Meek" value="Zigbee-Start">
                        <i class="fa fa-play-circle"></i>
                        Start
                        </button>

                        <button type="submit" class="Button ButtonA" name="Meek" value="Zigbee-Stop">
                        <i class="fa fa-stop-circle" aria-hidden="false"></i>
                        Stop
                        </button>

                        <button type="submit" class="Button ButtonA" name="Meek" value="Zigbee-Update">
                        <i class="fa-solid fa-wrench"></i>
                        Update
                        </button>

                        <button type="submit" class="Button ButtonA" name="Meek" value="Zigbee-Restart">
                        <i class="fa-solid fa-arrows-rotate"></i>
                        Restart
                        </button>
                </div>
        Last update :<br>xx-xx-xxxx
        
        </div></form>

</div>




<p><b>Credentials</b></p>

<div class="grid-container">
<div class="grid-item">
<h1>User Account</h1>
<form id="ScriptUser" method="POST" action="cupw.php">
  
    Username:
    <input id="field_username" title="Username must be 5 characters long and contain only letters, numbers and underscores." type="text" required="" pattern="\w+.{4,}" name="username">
  
 
    Password:
    <input id="field_pwd1" title="Password must contain at least 6 characters, including UPPER/lowercase and numbers." type="password" required="" pattern="(?=.*\d)(?=.*[a-z])(?=.*[A-Z]).{6,}" name="pwd1">


    Confirm Password:
    <input id="field_pwd2" title="Please enter the same Password as above." type="password" required="" pattern="(?=.*\d)(?=.*[a-z])(?=.*[A-Z]).{6,}" name="pwd2">


    <input type="submit" name="User" class="Button ButtonA" value="Submit">

</form>

<script type="text/javascript">
  document.addEventListener("DOMContentLoaded", function() {
    var checkPassword = function(str)
    {
      var re = /^(?=.*\d)(?=.*[a-z])(?=.*[A-Z]).{6,}$/;
      return re.test(str);
    };
    var checkForm = function(e)
    {
      if(this.username.value.length < 5)  {
        alert("Error: Username must be 5 characters or longer!");
        this.username.focus();
        e.preventDefault();
        return;
      }
      re = /^\w+$/;
      if(!re.test(this.username.value)) {
        alert("Error: Username must contain only letters, numbers and underscores!");
        this.username.focus();
        e.preventDefault();
        return;
      }
      if(this.pwd1.value != "" && this.pwd1.value == this.pwd2.value) {
        if(!checkPassword(this.pwd1.value)) {
          alert("The password you have entered is not valid!");
          this.pwd1.focus();
          e.preventDefault();
          return;
        }
      } else {
        alert("Error: Please check that you've entered and confirmed your password!");
        this.pwd1.focus();
        e.preventDefault();
        return;
      }
      alert("Your User credentials are now changed. Please make sure to use the new User credentials!");
    };
    var myForm = document.getElementById("ScriptUser");
    myForm.addEventListener("submit", checkForm, true);
    var supports_input_validity = function()
    {
      var i = document.createElement("input");
      return "setCustomValidity" in i;
    }

    if(supports_input_validity()) {
      var usernameInput = document.getElementById("field_username");
      usernameInput.setCustomValidity(usernameInput.title);

      var pwd1Input = document.getElementById("field_pwd1");
      pwd1Input.setCustomValidity(pwd1Input.title);

      var pwd2Input = document.getElementById("field_pwd2");
      usernameInput.addEventListener("keyup", function(e) {
        usernameInput.setCustomValidity(this.validity.patternMismatch ? usernameInput.title : "");
      }, false);

      pwd1Input.addEventListener("keyup", function(e) {
        this.setCustomValidity(this.validity.patternMismatch ? pwd1Input.title : "");
        if(this.checkValidity()) {
          pwd2Input.pattern = RegExp.escape(this.value);
          pwd2Input.setCustomValidity(pwd2Input.title);
        } else {
          pwd2Input.pattern = this.pattern;
          pwd2Input.setCustomValidity("");
        }
      }, false);

      pwd2Input.addEventListener("keyup", function(e) {
        this.setCustomValidity(this.validity.patternMismatch ? pwd2Input.title : "");
      }, false);

    }

  }, false);
</script>

<script type="text/javascript">
  if(!RegExp.escape) {
    RegExp.escape = function(s) {
      return String(s).replace(/[\\^$*+?.()|[\]{}]/g, '\\$&');
    };
  }
</script>
</div>

<div class="grid-item">
<h1>Admin Account</h1>
<form id="ScriptAdmin" method="POST" action="capw.php">
  
    Username:
    <input id="field_username" title="Username must be 5 characters long and contain only letters, numbers and underscores." type="text" required="" pattern="\w+.{4,}" name="username">
  
 
    Password:
    <input id="field_pwd1" title="Password must contain at least 6 characters, including UPPER/lowercase and numbers." type="password" required="" pattern="(?=.*\d)(?=.*[a-z])(?=.*[A-Z]).{6,}" name="pwd1">


    Confirm Password:
    <input id="field_pwd2" title="Please enter the same Password as above." type="password" required="" pattern="(?=.*\d)(?=.*[a-z])(?=.*[A-Z]).{6,}" name="pwd2">


    <input type="submit" name="Admin" class="Button ButtonA" value="Submit">

</form>

<script type="text/javascript">
  document.addEventListener("DOMContentLoaded", function() {
    var checkPassword = function(str)
    {
      var re = /^(?=.*\d)(?=.*[a-z])(?=.*[A-Z]).{6,}$/;
      return re.test(str);
    };
    var checkForm = function(e)
    {
      if(this.username.value.length < 5)  {
        alert("Error: Username must be 5 characters or longer!");
        this.username.focus();
        e.preventDefault();
        return;
      }
      re = /^\w+$/;
      if(!re.test(this.username.value)) {
        alert("Error: Username must contain only letters, numbers and underscores!");
        this.username.focus();
        e.preventDefault();
        return;
      }
      if(this.pwd1.value != "" && this.pwd1.value == this.pwd2.value) {
        if(!checkPassword(this.pwd1.value)) {
          alert("The password you have entered is not valid!");
          this.pwd1.focus();
          e.preventDefault();
          return;
        }
      } else {
        alert("Error: Please check that you've entered and confirmed your password!");
        this.pwd1.focus();
        e.preventDefault();
        return;
      }
      alert("Your new ADMIN Username and Password are qued to be changed. Please note that within a minute, you will not able to login with your old ADMIN Username and Password!");
    };
    var myForm = document.getElementById("ScriptAdmin");
    myForm.addEventListener("submit", checkForm, true);
    var supports_input_validity = function()
    {
      var i = document.createElement("input");
      return "setCustomValidity" in i;
    }


    if(supports_input_validity()) {
      var usernameInput = document.getElementById("field_username");
      usernameInput.setCustomValidity(usernameInput.title);

      var pwd1Input = document.getElementById("field_pwd1");
      pwd1Input.setCustomValidity(pwd1Input.title);

      var pwd2Input = document.getElementById("field_pwd2");
      usernameInput.addEventListener("keyup", function(e) {
        usernameInput.setCustomValidity(this.validity.patternMismatch ? usernameInput.title : "");
      }, false);

      pwd1Input.addEventListener("keyup", function(e) {
        this.setCustomValidity(this.validity.patternMismatch ? pwd1Input.title : "");
        if(this.checkValidity()) {
          pwd2Input.pattern = RegExp.escape(this.value);
          pwd2Input.setCustomValidity(pwd2Input.title);
        } else {
          pwd2Input.pattern = this.pattern;
          pwd2Input.setCustomValidity("");
        }
      }, false);

      pwd2Input.addEventListener("keyup", function(e) {
        this.setCustomValidity(this.validity.patternMismatch ? pwd2Input.title : "");
      }, false);

    }

  }, false);
</script>

<script type="text/javascript">
  if(!RegExp.escape) {
    RegExp.escape = function(s) {
      return String(s).replace(/[\\^$*+?.()|[\]{}]/g, '\\$&');
    };
  }
</script>
</div>

<div class="grid-item">
<h1>MQTT Account</h1>
<form id="ScriptMqtt" method="POST" action="cmqtpw.php">
  
    Username:
    <input id="field_username" title="Username must be 5 characters long and contain only letters, numbers and underscores." type="text" required="" pattern="\w+.{4,}" name="username">
  
 
    Password:
    <input id="field_pwd1" title="Password must contain at least 6 characters, including UPPER/lowercase and numbers." type="password" required="" pattern="(?=.*\d)(?=.*[a-z])(?=.*[A-Z]).{6,}" name="pwd1">


    Confirm Password:
    <input id="field_pwd2" title="Please enter the same Password as above." type="password" required="" pattern="(?=.*\d)(?=.*[a-z])(?=.*[A-Z]).{6,}" name="pwd2">


    <input type="submit" name="MQTT" class="Button ButtonA" value="Submit">

</form>

<script type="text/javascript">
var reader = new XMLHttpRequest() || new ActiveXObject('MSXML2.XMLHTTP');

function loadFile() {
    reader.open('get', 'files/mqtt', true);
    reader.onreadystatechange = displayContents;
    reader.send(null);
}
function displayContents() {
    if(reader.readyState==4) {
        var el = document.getElementById('main');
        el.innerHTML = reader.responseText;
    }
}

</script>

<details>
<summary>Show/Hide MQTT Login data</summary>
<font color="red">
<?php
$file = fopen("mqtt","r");
while(! feof($file))
  {
echo"Username : ";
echo fgets($file). "<br />";
echo"Password : ";
echo fgets($file). "<br />";
break;
  }
fclose($file);
?>

<?php
$file = fopen("port","r");
while(! feof($file))
  {
echo fgets($file). "<br />";
echo fgets($file). "<br />";
break;
  }
fclose($file);
?>
</details>


    
<div id="main">
    </div>
</div>





<script type="text/javascript">
  document.addEventListener("DOMContentLoaded", function() {
    var checkPassword = function(str)
    {
      var re = /^(?=.*\d)(?=.*[a-z])(?=.*[A-Z]).{6,}$/;
      return re.test(str);
    };
    var checkForm = function(e)
    {
      if(this.username.value.length < 5)  {
        alert("Error: Username must be 5 characters or longer!");
        this.username.focus();
        e.preventDefault();
        return;
      }
      re = /^\w+$/;
      if(!re.test(this.username.value)) {
        alert("Error: Username must contain only letters, numbers and underscores!");
        this.username.focus();
        e.preventDefault();
        return;
      }
      if(this.pwd1.value != "" && this.pwd1.value == this.pwd2.value) {
        if(!checkPassword(this.pwd1.value)) {
          alert("The password you have entered is not valid!");
          this.pwd1.focus();
          e.preventDefault();
          return;
        }
      } else {
        alert("Error: Please check that you've entered and confirmed your password!");
        this.pwd1.focus();
        e.preventDefault();
        return;
      }
    alert("Your new MQTT Username and Password are qued to be changed. Please note that within a minute, your not able to login with your old MQTT Username and Password!");
    };
    var myForm = document.getElementById("ScriptMqtt");
    myForm.addEventListener("submit", checkForm, true);
    var supports_input_validity = function()
    {
      var i = document.createElement("input");
      return "setCustomValidity" in i;
    }

    if(supports_input_validity()) {
      var usernameInput = document.getElementById("field_username");
      usernameInput.setCustomValidity(usernameInput.title);

      var pwd1Input = document.getElementById("field_pwd1");
      pwd1Input.setCustomValidity(pwd1Input.title);

      var pwd2Input = document.getElementById("field_pwd2");
      usernameInput.addEventListener("keyup", function(e) {
        usernameInput.setCustomValidity(this.validity.patternMismatch ? usernameInput.title : "");
      }, false);

      pwd1Input.addEventListener("keyup", function(e) {
        this.setCustomValidity(this.validity.patternMismatch ? pwd1Input.title : "");
        if(this.checkValidity()) {
          pwd2Input.pattern = RegExp.escape(this.value);
          pwd2Input.setCustomValidity(pwd2Input.title);
        } else {
          pwd2Input.pattern = this.pattern;
          pwd2Input.setCustomValidity("");
        }
      }, false);

      pwd2Input.addEventListener("keyup", function(e) {
        this.setCustomValidity(this.validity.patternMismatch ? pwd2Input.title : "");
      }, false);

    }

  }, false);
</script>

<script type="text/javascript">
  if(!RegExp.escape) {
    RegExp.escape = function(s) {
      return String(s).replace(/[\\^$*+?.()|[\]{}]/g, '\\$&');
    };
  }
</script>
</div>



<p>OpenVPN Section</p>


<div class="grid-container">
<div class="grid-item">


<script type="text/javascript">
var reader = new XMLHttpRequest() || new ActiveXObject('MSXML2.XMLHTTP');

function loadFile() {
    reader.open('get', 'files/mqtt', true); 
    reader.onreadystatechange = displayContents;
    reader.send(null);
}
function displayContents() {
    if(reader.readyState==4) {
        var el = document.getElementById('main');
        el.innerHTML = reader.responseText;
    }
}

</script>




<br>
<br>

<details>
    <summary>Show/Hide</summary>
        Username: xxxxxx
        <br>
        Password: xxxxxx
</details>
<br><br>



</div>
</div>
<p>Nieuw</p>


</body></html>

<?php
if (isset($_POST['Meek'])) {
$file = $_POST['Meek'];
     touch('command/'.$file);
}
?>
