<?php

##Pulldown for FS20-Devices


		$orders=array("on","off","dimup","dimdown","on-for-timer","off-for-timer","dim06%","dim12%",
			"dim18%","dim25%","dim31%","dim37%","dim43%","dim50%","dim56%","dim62%","dim68%",
			"dim75%","dim81%","dim87%","dim93%","dim100%","dimupdown","on-old-for-timer","reset",
			"sendstate","timer","toggle");

		echo "
		<tr>
		<td colspan=1 align=right $bg2><font $fontcolor3>FS20: </font></td><td align=left $bg2><font $fontcolor3>
		<form action=$forwardurl method='POST'>
		<input type=hidden name=showfht value=$showfht>
		<input type=hidden name=showhms value=$showhms>
		<input type=hidden name=showmenu value=$showmenu>
		<input type=hidden name=Action value=exec2>
		
		<select name=atorder size=1>
		<option></option>;
		<option>at</option></select>
		
		<select name=attime size=1>
		<option></option>;";
		for ($m=0; $m < 24; $m++)
       	        {
			if ( $m < 10) $m = '0'.$m;
			for ($k=0; $k < 60; $k=$k+2)
		        {	
				if ( $k < 10) $k = '0'.$k;
			  	echo "<option>$m:$k:00</option>";
			}
		}
					
		echo"</select>";




		echo"
		set 
		<select name=fs20dev size=1>
		<option></option>";
		for ($m=0; $m < count($fs20devs); $m++)
                        {
				echo $fs20dev;
				if ($fs20dev==$fs20devs[$m])
				{
					echo "<option selected>$fs20devs[$m]</option>";
				} else {
					echo "<option>$fs20devs[$m]</option>";
				}
			};

		echo "
		</select><select name=orderpulldown size=1>
		<option></option>";
		
		for ($m=0; $m < count($orders); $m++)
                        {
				if ($orderpulldown==$orders[$m])
				{
					echo "<option selected>$orders[$m]</option>";
				} else {
					echo "<option>$orders[$m]</option>";
				}
			};

		function mknullfs20($zahl,$stellen) {
		for($i=strlen($zahl);$i<$stellen;$i++){
		$zahl="0" . $zahl;
		}
		return $zahl;
		}
 
		echo "</select>
		<select name=valuetime size=1>     ### <------ valuetime mu� eindeutig werden !!! 
		<option></option>";
		echo "<option value=0>HH:MM:SS:MS</option>";
		echo "<option value=0>00:00:00:00</option>";
		echo "<option value=0.25>00:00:00:25</option>";
		echo "<option value=0.5>00:00:00:50</option>";
		echo "<option value=0.75>00:00:00:75</option>";
		echo "<option value=1>00:00:01:00</option>";
		echo "<option value=1.25>00:00:01:25</option>";
		echo "<option value=1.5>00:00:01:50</option>";
		echo "<option value=1.75>00:00:01:75</option>";
		echo "<option value=2>00:00:02:00</option>";
		echo "<option value=2.25>00:00:02:25</option>";
		echo "<option value=2.5>00:00:02:50</option>";
		echo "<option value=2.75>00:00:02:75</option>";
		echo "<option value=3>00:00:03:00</option>";
		echo "<option value=3.25>00:00:03:25</option>";
		echo "<option value=3.5>00:00:03:50</option>";
		echo "<option value=3.75>00:00:03:75</option>";
		echo "<option value=4>00:00:04:00</option>";
		echo "<option value=4.5>00:00:04:50</option>";
		echo "<option value=5>00:00:05:00</option>";
		echo "<option value=5.5>00:00:05:50</option>";
		echo "<option value=6>00:00:06:00</option>";
		echo "<option value=6.5>00:00:06:50</option>";
		echo "<option value=7>00:00:07:00</option>";
		echo "<option value=7.5>00:00:07:50</option>";
		for ($m=8; $m < 15360; $m++) {
       	                  if ( $m > 16) $m = $m+1;
       	                  if ( $m > 32) $m = $m+2;
       	                  if ( $m > 64) $m = $m+4;
       	                  if ( $m > 128) $m = $m+8;
       	                  if ( $m > 256) $m = $m+16;
       	                  if ( $m > 512) $m = $m+32;
       	                  if ( $m > 1024) $m = $m+64;
       	                  if ( $m > 2048) $m = $m+128;
       	                  if ( $m > 4096) $m = $m+256;
       	                  if ( $m > 8192) $m = $m+512;
       	                  if ( $m > 7)
					$sek=$m;
					$std=floor($sek/3600);
					$min=floor(($sek-$std*3600)/60);
					$sec=$sek-$std*3600-$min*60;
					$std=mknullfs20($std,2);
					$min=mknullfs20($min,2);
					$sec=mknullfs20($sec,2); 
				echo "<option value=$m>$std:$min:$sec</option>";}
		
		echo"</select>
		<input type=submit value='go!'></form></td></tr>";

#		<select name=valuetime size=1>
#		<option></option>";
#		for ($m=0; $m < 6000; $m++)
#       	                 {if ( $m > 20) $m = $m+4;
#       	                 if ( $m > 60) $m = $m+55;
#				echo "<option>$m</option>";}
#		
#		echo"</select>

?>
