# Common variables and routines for dealing with data from Urban Terror 4.1
# Author: Jeff Genovy (jgen)
# August 2009

my %urt_gtypes = (
	0 => 'Free for All',
	1 => 'Invalid',
	2 => 'Invalid',
	3 => 'Team Deathmatch',
	4 => 'Team Survivor',
	5 => 'Follow the Leader',
	6 => 'Capture & Hold',
	7 => 'Capture the Flag',
	8 => 'Bomb & Defuse'
);

my @urt_g_gears = (
	'Grenades', 'Snipers', 'Spas', 'Pistols', 'Automatics', 'Negev'
);

my %urt_weapons = (
	40 => 'UT_MOD_GOOMBA',
	38 => 'UT_MOD_M4',
	37 => 'UT_MOD_HK69_HIT',
	35 => 'UT_MOD_NEGEV',
	32 => 'UT_MOD_SLAPPED',
	31 => 'UT_MOD_SPLODED',
	30 => 'UT_MOD_AK103',
	28 => 'UT_MOD_SR8',
	25 => 'UT_MOD_HEGRENADE',
	24 => 'UT_MOD_KICKED',
	23 => 'UT_MOD_BLED',
	22 => 'UT_MOD_HK69',
	21 => 'UT_MOD_PSG1',
	20 => 'UT_MOD_G36',
	19 => 'UT_MOD_LR300',
	18 => 'UT_MOD_MP5K',
	17 => 'UT_MOD_UMP45',
	16 => 'UT_MOD_SPAS',
	15 => 'UT_MOD_DEAGLE',
	14 => 'UT_MOD_BERETTA',
	13 => 'UT_MOD_KNIFE_THROWN',
	12 => 'UT_MOD_KNIFE',
	10 => 'MOD_CHANGE_TEAM',
	9 => 'MOD_TRIGGER_HURT',
	7  => 'MOD_SUICIDE',
	6  => 'MOD_FALLING',
	1  => 'MOD_WATER'
);

my %urt_weapons_common_names = (
	40 => 'Goomba Stomp',
	38 => 'M-4',
	37 => 'Hit with a HK69 Grenade',
	35 => 'IMI Negev LMG',
	32 => 'SLAPPED to Death',
	31 => '\'SPLODED',
	30 => 'Kalashnikov AK-103',
	28 => 'Remington SR-8',
	25 => 'High Energy Grenade',
	24 => 'Booted',
	23 => 'Bled to Death',
	22 => 'Heckler & Koch HK69',
	21 => 'Heckler & Koch PSG-1',
	20 => 'Heckler & Koch G36E',
	19 => 'ZM Weapons LR300ML',
	18 => 'Heckler & Koch MP5K',
	17 => 'Heckler & Koch UMP45',
	16 => 'Franchi SPAS12 Shotgun',
	15 => 'IMI .50 AE Desert Eagle',
	14 => 'Beretta 92FS',
	13 => 'Knife (Thrown)',
	12 => 'Knife (Cut)',
	10 => 'Changed Team',
	9  => 'Map Damage Trigger',
	7  => 'Suicide',
	6  => 'Fell to Death',
	1  => 'Drowned'
);


# This function takes the g_gear value [0 - 63] and returns a string with the Allowed weapon types.
sub urt_gear2str( $ ) {
	my $value = shift;
	my $txt = '';
	my $i = 0;

	if ($value >= 64 || $value < 0)
	{
		warn 'Invalid gear value <'. $value .'> given to sub gear2str($)';
		return 'Invalid gear value.';
	}
	
	for ($i = 5; $i >=0 ; $i--)
	{
		if ( $value >= 2**$i )
		{	$value -= 2**$i;	}
		else
		{	
			if ($txt)
				{	$txt .= ', ' . $urt_g_gears[$i];	}
			else
				{	$txt .= $urt_g_gears[$i];	}
		}
	}

	return $txt;
}



1; # Necessary for include files
