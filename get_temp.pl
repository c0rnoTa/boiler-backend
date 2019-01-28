#!/usr/bin/perl

# Подгружаем используемые модули
use warnings;
use POSIX;
use DBI;
use LWP::UserAgent;
use XML::Simple;

# Объявляем переменные
my $period = 60;	# Период опроса датчиков
my $debug = 1;		# Включение режима отладки
my $emu = 0;		# Эмуляция работы датчиков
my $w1_slaves_file = '/sys/bus/w1/devices/w1_bus_master1/w1_master_slaves';
my $database = "/home/pi/database.sqlite";
my $boiler = "http://192.168.10.82/status.xml";
my @results;
my $parser = new XML::Simple;

## Сама программа
&main;

## Основная функция программы
sub main {
	print "Сервис работает в режиме имитации\n" if $emu;
	$dsn = "DBI:SQLite:dbname=$database";
	$dbh = DBI->connect($dsn, "", "", { RaiseError => 1 }) or die $DBI::errstr;
	print "Подключилась к БД " . $database . "\n" if $debug;
	$ua = LWP::UserAgent->new;
	$ua->timeout(10);

	&check_modules; # Проверяем загруженные модули
	&get_device_IDs; # Получаем идентификаторы датчиков
	&get_config; # Получаем конфигурацию для датчиков

	while (1) {
		&write_data;
		&http_get;
		sleep($period);
	}
	$dbh->disconnect();
}

## Проверяет модули в системе
sub check_modules {
	print "Проверяю наличие модулей 1-wire в системе...\n" if $debug;
	$mods = `cat /proc/modules`;
	if ($mods =~ /w1_gpio/ && $mods =~ /w1_therm/) {
		print "Модули загружены \n" if $debug;
	} else {
		print "Загружаю модули \n" if $debug;
		# Вот эту кривь надо переписать или исключить вообще
		`sudo modprobe w1-gpio`;
		`sudo modprobe w1-therm`;
	}
}

## Получает ID подключенных датчиков
## @return array @deviceIDs 
sub get_device_IDs {
	print "Ищу идентификаторы датчиков... " if $debug;
	if ($emu) {
		# Эмуляция работы программы
		for (my $i=1; $i <= 2; $i++) {
			$sensorID = "99-0000000" . $i;
    		push @deviceIDs, $sensorID;
    		$dbh->do('INSERT OR IGNORE INTO `sensors` (id) VALUES (?)',  undef,  $sensorID);		
		}
	} else {
		# Реальная работа программы
		open(my $fh, "<", $w1_slaves_file) or die("Failed to open file: $!\n");
		while(<$fh>) { 
		    chomp;
		    $sensorID = $_;
    		push @deviceIDs, $sensorID;
    		$dbh->do('INSERT OR IGNORE INTO `sensors` (id) VALUES (?)',  undef,  $sensorID);
		}
		close $fh;
	}
	print "нашла " . scalar @deviceIDs . "\n" if $debug;
}

## Получает конфигурацию для каждого датчика
## @return array @deviceIDs
sub get_config {
	@config = ();
	while (my ($key, $device) = each @deviceIDs) {
		print "Получаю конфигурацю для датчика " . "[" . $key . "] " . $device . "\n" if $debug;
		$sql = 'SELECT `tmin`, `tmax` FROM `config` WHERE sensorid = ? LIMIT 1';
    	$sth = $dbh->prepare($sql);
    	$sth->execute($device);
    	$tMin = 10;
    	$tMax = 20;
    	if ($dbConf = $sth->fetchrow_hashref) {
    		$tMin = $dbConf->{tmin} + 0;
    		$tMax = $dbConf->{tmax} + 0;
    	} else {
    		print "В базе данных нет конфигурации для " . $device . "\n" if $debug;
    	}
    	print "Устанавливаю значения алармов для " . $device . ": " . $tMin . ' / ' .  $tMax . "\n" if $debug;
    	%conf = ( tMin => $tMin,  tMax => $tMax);
    	$config[ $key ] = \%conf;
	}
}

## Читает данные с датчика
## @param string deviceID
## @return string temperature
sub read_device {
	# Возвращает 9999 при ошибке чтения с датчика
    $ret = 9999;

    $deviceID = $_[0];
    $deviceID =~ s/\R//g;
    print "Читаю температуру с датчика " . $deviceID . ": " if $debug;
	
	if ($emu) {
		# Эмуляция работы программы
		$range = 30000;
		$minimum = 0;
		$ret = (int(rand($range)) + $minimum)/1000;
		print $ret . "\n" if $debug;
	} else {
		# Реальная работа программы
	    $sensordata = `cat /sys/bus/w1/devices/${deviceID}/w1_slave 2>&1`;
    
    	if ( index( $sensordata, 'YES' ) != -1 ) {
    		$sensordata =~ /t=(\D*\d+)/i;
    		$sensordata = (($1/1000));
    		$ret = $sensordata;
    		print $ret . "\n" if $debug;
    	} else {
    		print "CRC ошибка\n" if $debug;
    	}
	}
    return $ret;
}

## Опрос датчиков и запись значений в БД
## @retern null
sub write_data {
	$i = 0;
	print "Опрашиваем датчики...\n" if $debug;
	while (my ($key, $device) = each @deviceIDs) {
		$reading = &read_device($device);
		$curentTime = strftime("%Y-%m-%d %H:%M:%S", localtime(time));
		if ($reading != "9999") {
			# Проверяем алармы
			%conf = %{$config[$key]};
			if ( $conf{tMin} > $reading ) {
				$alarm = 'MIN';
			} elsif ($conf{tMax} < $reading) {
				$alarm = 'MAX';
			} else {
				$alarm = '';
			}
			# Записываем данные
			%data = ( curTime => $curentTime,  deviceID => $device, temp => $reading, alarm => $alarm);
			print "[" . $data{curTime} . "] " . $data{deviceID} . ": " . $data{temp} . " ALARM: " . $data{alarm} ."\n" if $debug;
			$dbh->do('INSERT INTO `tempdata` ( datetime, id, temp, alarm) VALUES (?, ?, ?, ?)', undef, $data{curTime}, $data{deviceID}, $data{temp}, $data{alarm}) or die $DBI::errstr;
			$dbh->do('UPDATE `sensors` SET `lastread` = ?, `current` = ? WHERE `id` = ?', undef, $data{curTime}, $data{temp}, $data{deviceID}) or die $DBI::errstr;
			$i++;
		}
	}
	print "Всего датчиков с корректными данными: " . $i . " \n" if $debug;
}

## Опрос состояния котла и запись значений в БД
sub http_get {
	# set custom HTTP request header fields
	my $req = HTTP::Request->new(GET => $boiler);
	#$req->header('content-type' => 'application/json');
	#$req->header('x-auth-token' => 'kfksj48sdfj4jd9d');

	print "Получаю состояние котла...\n" if $debug;
	my $resp = $ua->request($req);
	$curentTime = strftime("%Y-%m-%d %H:%M:%S", localtime(time));
	if ($resp->is_success) {
	    my $message = $resp->decoded_content;
	    $message = $parser->XMLin($message);

	    # Записываем данные
	    %kotel = ( 
		T_KOTLA => $message->{val0} . "." . $message->{val6},
		T_OBRATKI => $message->{val1} . "." . $message->{val7},
		MOSHNOST => $message->{val2} . "." . $message->{val10},
		RASCHOD => $message->{val3},
		PLAMJA => $message->{val4},
		REZHIM => $message->{val5},
		T_KOMNATY1 => $message->{val11});
            print "[" . $curentTime . "] T_KOTLA:" .$kotel{T_KOTLA}. " T_OBRATKI:" . $kotel{T_OBRATKI} . " MOSHNOST:" . $kotel{MOSHNOST} . " RASCHOD:" . $kotel{RASCHOD} . " PLAMJA:" . $kotel{PLAMJA} . " REZHIM:" . $kotel{REZHIM} . " T_KOMNATY1:" . $kotel{T_KOMNATY1} . "\n" if $debug;
            $dbh->do('INSERT INTO `gorelkadata` ( datetime, val0, val1, val2, val3, val4, val5, val6) VALUES (?, ?, ?, ?, ?, ?, ?, ?)', undef, $curentTime, $kotel{T_KOTLA}, $kotel{T_OBRATKI}, $kotel{MOSHNOST}, $kotel{RASCHOD}, $kotel{PLAMJA}, $kotel{REZHIM}, $kotel{T_KOMNATY1}) or die $DBI::errstr;
	} else {
	    print "HTTP GET error code: ", $resp->code, " message: ", $resp->message, "\n" if $debug;
	    $dbh->do('INSERT INTO `gorelkadata` ( datetime, error) VALUES (?, ?)', undef, $curentTime, $resp->code) or die $DBI::errstr;
	}
}
