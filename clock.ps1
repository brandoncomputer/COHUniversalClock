#WARNING: You can run Clock. But you can't edit custom windows while running Clock.
#That means close clock. Then edit custom windows. Then run clock.
#Clock always saves a copy of CUSTOM.WINDOW to its own path before starting to tick.
#That means if Clock breaks your CUSTOM.WINDOW, you have ONE chance to copy it back to the game directory.
#If you run clock twice with a broken CUSTOM.WINDOW, then you ruined your chance.
#The exception to this is the empty file error that sometimes occurs, Clock does not copy empty files, this gives you more chances to fix.

#If you already have a CUSTOM.WINDOW file, you need to know clock modifies lines 3, 4, 5, and 6. Populate these lines with '	Button "Edit Me" nop' before running Clock.

# Source file. Edit this as needed.
$filePath = "C:\Games\Homecoming\data\customwindows\CUSTOM.WINDOW"

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Create the form
$form = New-Object System.Windows.Forms.Form
$form.Text = "City of Heroes Game Clock"
$form.Size = New-Object System.Drawing.Size(400,100)
$form.StartPosition = "CenterScreen"
$form.TopMost = $true

# Display label
$labelClock = New-Object System.Windows.Forms.Label
$labelClock.Text = ""
$labelClock.Location = New-Object System.Drawing.Point(10,10)
$labelClock.Size = New-Object System.Drawing.Size(400,40)
$labelClock.Font = New-Object System.Drawing.Font("Arial",16,[System.Drawing.FontStyle]::Bold)
$form.Controls.Add($labelClock)

<# 
Timer setup
1.25 seconds = 1 in-game minute, 
Increase the interval to prevent crashes.
This timer does not keep time, it's just how often the update fires.
Best practice is to exit the clock before editing custom window macros.
#>

write-host sourceExists $sourceExists
write-host sourceIsEmpty $sourceIsEmpty
write-host destinationExists $destinationExists


$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 1250  

$directoryPath = Split-Path $filePath

# Destination: clock script's directory
$destinationPath = Join-Path $PSScriptRoot "CUSTOM.WINDOW"

# Ensure source directory exists
if (-not (Test-Path $directoryPath)) {
    New-Item -Path $directoryPath -ItemType Directory -Force
    Write-Host "Created missing directory: $directoryPath"
}

# Check if source file exists
$sourceExists = Test-Path $filePath

# Check if destination file exists
$destinationExists = Test-Path $destinationPath

# Check if source file is empty (zero-byte or whitespace-only)
$sourceIsEmpty = $false
if ($sourceExists) {
    $fileInfo = Get-Item $filePath
    if ($fileInfo.Length -eq 0) {
        $sourceIsEmpty = $true
    } else {
        $content = Get-Content $filePath -Raw
        if ($null -eq $content -or $content -match '^\s*$') {
            $sourceIsEmpty = $true
        }
    }
}

# If source is empty AND destination exists → restore from destination
if ($sourceIsEmpty -and $destinationExists) {
    Copy-Item -Path $destinationPath -Destination $filePath -Force
    Write-Host "CUSTOM.WINDOW was empty—restored from clock directory."
}

# If source is missing OR empty AND destination does NOT exist → write default stub to source

if ((-not $sourceExists -or $sourceIsEmpty) -and -not $destinationExists) {
@'
	
Window Clock 0.0 0.0 200 100
	Button "Edit Me" nop
	Button "Edit Me" nop
	Button "Edit Me" nop
	Button "Edit Me" nop
	Open 1
End
'@ | Set-Content -Path $filePath -Force
    Write-Host "CUSTOM.WINDOW was missing or empty and no destination file existed—wrote default stub to source."

    # Wait exactly 1 second before proceeding
    Start-Sleep -Seconds 1
}

# Only copy source into clock directory if it exists AND is not empty
if ((Test-Path $filePath) -and (-not $sourceIsEmpty)) {
    Copy-Item -Path $filePath -Destination $destinationPath -Force
    Write-Host "CUSTOM.WINDOW copied into clock directory from source."
} elseif (-not $sourceExists) {
    Write-Host "CUSTOM.WINDOW source file does not exist—skipped copy to clock directory."
} else {
    Write-Host "CUSTOM.WINDOW source file is empty—skipped copy to clock directory."
}


$global:lastRecordedDay = -1
$global:currentInGameDay = -1

# Format time as 12-hour with AM/PM
function Format-Time {
    param ($hour, $minute)
    $suffix = if ($hour -ge 12) { "PM" } else { "AM" }
    $displayHour = $hour % 12
    if ($displayHour -eq 0) { $displayHour = 12 }
	$minute = [int]$minute
	$hour = [int]$hour
    return ("{0}:{1:D2} {2}" -f $displayHour, $minute, $suffix)
}

# Get real-time offset from last half-hour mark
function Get-GameTime {
    $now = [DateTime]::UtcNow
	$utcToday = [DateTime]::UtcNow.Date
	$base = if ($now.Minute -ge 30) {
		$utcToday.AddHours($now.Hour).AddMinutes(30)
	} else {
		$utcToday.AddHours($now.Hour)
	}
    $elapsed = ($now - $base).TotalSeconds
    $inGameMinutes = [math]::Floor($elapsed / 1.25)
    $hour = [math]::Floor($inGameMinutes / 60)
    $minute = $inGameMinutes % 60 
    return @{ Hour = $hour; Minute = $minute }
}

function Get-NthWeekdayOfMonth($year, $month, $weekdayName, $n) {
    $weekdayIndex = [enum]::GetValues([DayOfWeek]) | Where-Object { $_.ToString() -eq $weekdayName }
    $date = [datetime]::new($year, $month, 1)
    $count = 0
    while ($date.Month -eq $month) {
        if ($date.DayOfWeek -eq $weekdayIndex) {
            $count++
            if ($count -eq $n) { return $date.Day }
        }
        $date = $date.AddDays(1)
    }
    return $null
}

function Get-LastWeekdayOfMonth($year, $month, $weekdayName) {
    $weekdayIndex = [enum]::GetValues([DayOfWeek]) | Where-Object { $_.ToString() -eq $weekdayName }
    $date = [datetime]::new($year, $month, [DateTime]::DaysInMonth($year, $month))
    while ($date.Month -eq $month) {
        if ($date.DayOfWeek -eq $weekdayIndex) { return $date.Day }
        $date = $date.AddDays(-1)
    }
    return $null
}

function Get-GameDate {
	$now = [DateTime]::UtcNow
    $daysInMonth = [DateTime]::DaysInMonth($now.Year, $now.Month)
	
	$reservedDays = @( )
	
	$reservedDays += $daysInMonth

	#Never skip Easter Sunday, Good Friday
	if ($now.Month -eq 3 -or $now.Month -eq 4) {
		$weekdayTargets = @('Sunday', 'Friday')
		foreach ($weekday in $weekdayTargets) {
			$weekdayIndex = [enum]::GetValues([DayOfWeek]) | Where-Object { $_.ToString() -eq $weekday }
			$date = [datetime]::new($now.Year, $now.Month, 1)
			while ($date.Month -eq $now.Month) {
				if ($date.DayOfWeek -eq $weekdayIndex) {
					$reservedDays += $date.Day
				}
				$date = $date.AddDays(1)
			}
		}
	}

	switch ($now.Month) {
		1  { $reservedDays += 1 }     # New Year's Day
		2  { $reservedDays += 14 }    # Valentine's Day
		6  { $reservedDays += 19 }    # Juneteenth
		7  { $reservedDays += 4 }     # Independence Day
		10 { $reservedDays += 31 }    # Halloween
		11 { $reservedDays += 11 }    # Veterans Day
		12 { $reservedDays += 24 }    # Christmas Eve
		12 { $reservedDays += 25 }    # Christmas
	}

	switch ($now.Month) {
		1 {  # January – MLK Day (3rd Monday)
			$reservedDays += Get-NthWeekdayOfMonth $now.Year 1 'Monday' 3
		}
		2 {  # February – Presidents' Day (3rd Monday)
			$reservedDays += Get-NthWeekdayOfMonth $now.Year 2 'Monday' 3
		}
		5 {  # May – Memorial Day (last Monday)
			$reservedDays += Get-LastWeekdayOfMonth $now.Year 5 'Monday'
		}
		9 {  # September – Labor Day (1st Monday)
			$reservedDays += Get-NthWeekdayOfMonth $now.Year 9 'Monday' 1
		}
		10 { # October – Columbus Day (2nd Monday)
			$reservedDays += Get-NthWeekdayOfMonth $now.Year 10 'Monday' 2
		}
		11 { # November – Thanksgiving (4th Thursday)
			$reservedDays += Get-NthWeekdayOfMonth $now.Year 11 'Thursday' 4
		}
	}

	$slotIndex = [math]::Floor(($now.Hour * 60 + $now.Minute) / 30)
    if ($slotIndex -ge 24) { $slotIndex = 23 }


	# Step 2: Generate evenly spaced day values
	$evenlySpaced = @( )
	for ($i = 0; $i -lt 24; $i++) {
		$mappedDay = [math]::Round(1 + ($i * ($daysInMonth - 1) / 23))
		$evenlySpaced += $mappedDay
	}

	# Step 3: Merge and deduplicate
	$mergedDays = $reservedDays + $evenlySpaced
	$uniqueDays = $mergedDays | Sort-Object | Get-Unique

	# Step 4: Trim to 24 slots
	while ($uniqueDays.Count -gt 24) {
		# Remove least critical day (e.g., closest to another)
		$closestGap = [int]::MaxValue
		$removeIndex = -1
		for ($i = 1; $i -lt $uniqueDays.Count - 1; $i++) {
			$gap = $uniqueDays[$i+1] - $uniqueDays[$i-1]
			if ($gap -lt $closestGap -and -not ($reservedDays -contains $uniqueDays[$i])) {
				$closestGap = $gap
				$removeIndex = $i
			}
		}
		if ($removeIndex -ge 0) {
			$uniqueDays = $uniqueDays[0..($removeIndex-1)] + $uniqueDays[($removeIndex+1)..($uniqueDays.Count-1)]
		} else {
			break
		}
	}

	$dayMap = $uniqueDays

	$expectedDay = if ($slotIndex -lt $dayMap.Count) { $dayMap[$slotIndex] } else { $dayMap[-1] }

    # Only update the day when in-game time hits 12:00 AM
    $gameTime = Get-GameTime
    if ($gameTime.Hour -eq 0 -and $gameTime.Minute -eq 0 -and $expectedDay -ne $global:lastRecordedDay) {
        $global:currentInGameDay = $expectedDay
        $global:lastRecordedDay = $expectedDay
    }

    # Fallback if not yet initialized
    if ($global:currentInGameDay -lt 1) {
        $global:currentInGameDay = $expectedDay
        $global:lastRecordedDay = $expectedDay
    }

    # Day of week calculation
    $day = $global:currentInGameDay
    $weekdays = @("Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday")
    $dayOfWeekIndex = ($day - 1) % 7
    $dayOfWeek = $weekdays[$dayOfWeekIndex]

    return "$dayOfWeek, $($now.ToString('MMMM')) $day, $($now.ToString('yyyy'))"
}


function Format-RealDate {
    $now = Get-Date
    return $now.ToString("MMMM d, yyyy")
}

$global:lastGameHour = -1
# Timer tick event
$timer.Add_Tick({
    $gameTime = Get-GameTime
	# Detect in-game midnight transition
	$formattedGameDate = Get-GameDate
	$expectedDay = $global:currentInGameDay

	if ($gameTime.Hour -eq 0 -and $global:lastGameHour -ne 0) {
		$global:currentInGameDay = $expectedDay
		$global:lastRecordedDay = $expectedDay
	}
	$global:lastGameHour = $gameTime.Hour
    $formattedGameTime = Format-Time $gameTime.Hour $gameTime.Minute

    $realNow = Get-Date
    $formattedRealTime = Format-Time $realNow.Hour $realNow.Minute
    $formattedRealDate = Format-RealDate
	    $labelClock.Text = " $formattedGameDate, $formattedGameTime"

    if (Test-Path $filePath) {
        $lines = Get-Content $filePath
        while ($lines.Count -lt 6) { $lines += "" }

        $newLine3 = "`tButton `"$formattedGameDate`""
        $newLine4 = "`tButton `"$formattedGameTime`""
		$newLine5 = "`tButton `"$formattedRealDate`""
		$newLine6 = "`tButton `"$formattedRealTime`""

        $changed = $false
        if ($lines[2] -ne $newLine3) { $lines[2] = $newLine3; $changed = $true }
        if ($lines[3] -ne $newLine4) { $lines[3] = $newLine4; $changed = $true }
        if ($lines[4] -ne $newLine5) { $lines[4] = $newLine5; $changed = $true }
        if ($lines[5] -ne $newLine6) { $lines[5] = $newLine6; $changed = $true }

        if ($changed) {
            Set-Content -Path $filePath -Value $lines
        }
    }
})

# Start ticking
$timer.Start()

# Run the form
[void]$form.ShowDialog()
