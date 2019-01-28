<?php
/**
 * Created by PhpStorm.
 * User: anton
 * Date: 28.01.19
 * Time: 14:45
 */

// Device ID
//$device = '10-0008028169fd';
$device = $_GET['id'];

// File path
$file = "/sys/bus/w1/devices/".$device."/w1_slave";

// Read file and get temp
$content = file($file);
$temp = explode(' ', $content[1]);
$temp = substr(trim($temp[9]),2);

// Return value
echo $temp/1000;