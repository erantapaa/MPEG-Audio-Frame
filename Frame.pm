#!/usr/bin/perl

package MPEG::Audio::Frame;

use strict;
use warnings;
use integer;

use overload '""' => \&asbin;

our $VERSION = 0.06;

# constants

my %version = (
	'00' => 1,
#	'01' => reserved
	'10' => 1,
	'11' => 0,
);

my %layer = (
#	'00' => reserved
	'01' => 2,
	'10' => 1,
	'11' => 0,
);

my @bitrates = (
		# 1   10  11  100  101  110  111  1000 1001 1010 1011 1100 1101 1110 # bits
	[	#v1
		[ 32, 64, 96, 128, 160, 192, 224, 256, 288, 320, 352, 384, 416, 448 ], # l1
		[ 32, 48, 56, 64,  80,  96,  112, 128, 160, 192, 224, 256, 320, 384 ], # l2
		[ 32, 40, 48, 56,  64,  80,  96,  112, 128, 160, 192, 224, 256, 320 ], # l3
	],
	[	#v2
		[ 32, 64, 96, 128, 160, 192, 224, 256, 288, 320, 352, 384, 416, 448 ], # l1
		[ 32, 48, 56, 64,  80,  96,  112, 128, 160, 192, 224, 256, 320, 384 ], # l2
		[ 8,  16, 24, 32,  40,  48,  56,  64,  80,  96,  112, 128, 144, 160 ], # l3 # unverified
	],
);

my %samples = (
	'11' => {
		'00' => 44100,
		'01' => 48000,
		'10' => 32000,
#		'11' => reserved
	},
	'10' => {
		'00' => 22050,
		'01' => 24000,
		'10' => 16000,
#		'11' => reserved
	},
	'00' => {
		'00' => 11025,
		'01' => 12000,
		'10' => 8000,
#		'11' => reserved
	}
);


# stolan from libmad, bin.c
my @crc_table = (
	0x0000, 0x8005, 0x800f, 0x000a, 0x801b, 0x001e, 0x0014, 0x8011,
	0x8033, 0x0036, 0x003c, 0x8039, 0x0028, 0x802d, 0x8027, 0x0022,
	0x8063, 0x0066, 0x006c, 0x8069, 0x0078, 0x807d, 0x8077, 0x0072,
	0x0050, 0x8055, 0x805f, 0x005a, 0x804b, 0x004e, 0x0044, 0x8041,
	0x80c3, 0x00c6, 0x00cc, 0x80c9, 0x00d8, 0x80dd, 0x80d7, 0x00d2,
	0x00f0, 0x80f5, 0x80ff, 0x00fa, 0x80eb, 0x00ee, 0x00e4, 0x80e1,
	0x00a0, 0x80a5, 0x80af, 0x00aa, 0x80bb, 0x00be, 0x00b4, 0x80b1,
	0x8093, 0x0096, 0x009c, 0x8099, 0x0088, 0x808d, 0x8087, 0x0082,

	0x8183, 0x0186, 0x018c, 0x8189, 0x0198, 0x819d, 0x8197, 0x0192,
	0x01b0, 0x81b5, 0x81bf, 0x01ba, 0x81ab, 0x01ae, 0x01a4, 0x81a1,
	0x01e0, 0x81e5, 0x81ef, 0x01ea, 0x81fb, 0x01fe, 0x01f4, 0x81f1,
	0x81d3, 0x01d6, 0x01dc, 0x81d9, 0x01c8, 0x81cd, 0x81c7, 0x01c2,
	0x0140, 0x8145, 0x814f, 0x014a, 0x815b, 0x015e, 0x0154, 0x8151,
	0x8173, 0x0176, 0x017c, 0x8179, 0x0168, 0x816d, 0x8167, 0x0162,
	0x8123, 0x0126, 0x012c, 0x8129, 0x0138, 0x813d, 0x8137, 0x0132,
	0x0110, 0x8115, 0x811f, 0x011a, 0x810b, 0x010e, 0x0104, 0x8101,

	0x8303, 0x0306, 0x030c, 0x8309, 0x0318, 0x831d, 0x8317, 0x0312,
	0x0330, 0x8335, 0x833f, 0x033a, 0x832b, 0x032e, 0x0324, 0x8321,
	0x0360, 0x8365, 0x836f, 0x036a, 0x837b, 0x037e, 0x0374, 0x8371,
	0x8353, 0x0356, 0x035c, 0x8359, 0x0348, 0x834d, 0x8347, 0x0342,
	0x03c0, 0x83c5, 0x83cf, 0x03ca, 0x83db, 0x03de, 0x03d4, 0x83d1,
	0x83f3, 0x03f6, 0x03fc, 0x83f9, 0x03e8, 0x83ed, 0x83e7, 0x03e2,
	0x83a3, 0x03a6, 0x03ac, 0x83a9, 0x03b8, 0x83bd, 0x83b7, 0x03b2,
	0x0390, 0x8395, 0x839f, 0x039a, 0x838b, 0x038e, 0x0384, 0x8381,

	0x0280, 0x8285, 0x828f, 0x028a, 0x829b, 0x029e, 0x0294, 0x8291,
	0x82b3, 0x02b6, 0x02bc, 0x82b9, 0x02a8, 0x82ad, 0x82a7, 0x02a2,
	0x82e3, 0x02e6, 0x02ec, 0x82e9, 0x02f8, 0x82fd, 0x82f7, 0x02f2,
	0x02d0, 0x82d5, 0x82df, 0x02da, 0x82cb, 0x02ce, 0x02c4, 0x82c1,
	0x8243, 0x0246, 0x024c, 0x8249, 0x0258, 0x825d, 0x8257, 0x0252,
	0x0270, 0x8275, 0x827f, 0x027a, 0x826b, 0x026e, 0x0264, 0x8261,
	0x0220, 0x8225, 0x822f, 0x022a, 0x823b, 0x023e, 0x0234, 0x8231,
	0x8213, 0x0216, 0x021c, 0x8219, 0x0208, 0x820d, 0x8207, 0x0202
);

sub CRC_POLY () { 0x8005 }

###

my @protbits = (
	[ 128, 256 ], # layer one
	undef,
	[ 136, 256 ], # layer three
);

# constructor and work horse

sub read {
	my $pkg = shift || return undef;
	my $fh = shift || return undef;
	
	# return unless fileno $fh # will fail on opened scalar ref, a la 5.8. not a Good Thing&trade;
	
	local $/ = "\xff"; # 8 bits of sync.
	
	my %header;	# the header hash thing
	my $offset;	# where in the handle
	my $behead; # the binary header data... what a fabulous pun.
	my $ok = undef;
	
	while (<$fh>){ # readline, readline, find me a header, make me a header, catch me a header. somewhate wasteful, perhaps.
		read $fh,my($header), 1; # read the first byte
		next unless (unpack("B3",$header))[0] eq '111';	# see if the sync remains
		#print "frame header found at ", unpack("H*",pack("I",$offset = tell($fh) - 2)), "\n";
		read $fh,$header,2,1; # the remaining bytes
	
		$behead = "\xff" . $header;
		$header = unpack("B*",$header);
		#print $header,"\n";
		(
			$header{sync},
			$header{version},
			$header{layer},
			$header{crc},
			$header{bitrate},
			$header{sample},
			$header{pad},
			$header{private},
			$header{chanmode},
			$header{modext},
			$header{copy},
			$header{home},
			$header{emph},
		) = map { substr($header,0,$_,'') } ( 3, 2, 2, 1, 4, 2, 1, 1, 2, 2, 1, 1, 2, ); #unpack("B[3]B[2]B[2]B[1]B[4]B[2]B[1]B[1]B[2]B[2]B[1]B[1]B[2]",$header); didn't work as expected. i should reread the docs, i guess... something about alignment, i  suppose.
		next if ( # invalid header tests		# some of these are reserved for future use, and will fail, others are simply illegal, and will (surprisingly) also fail
			$header{sync}		ne '111'	or	# good form, even though we already checked
			$header{version}	eq '01'		or	# 01 is nonexistent, hence the header is noughty
			$header{layer}		eq '00'		or	# no such layer, again
			$header{bitrate}	eq '1111'	or	# this is an invalid setting for the bitrate
			$header{sample}		eq '11'		or	# yet another illegal value
			$header{emph}		eq '10'		or	# and another.
			not scalar keys %header # did something go wrong?
		);
		
		$header{sync} = '11111111' . $header{sync}; # make it 'real'
		
		$offset = tell($fh) - 2;
		
		$ok = 1;	
			
		last; # were done reading for the header
	}
	
	use Data::Dumper;
	
	return undef unless $ok;
	
	my $crc;
	read $fh,$crc,2 unless $header{crc}; # checksum bits
	
	my $bitrate	= $bitrates[$version{$header{version}}][$layer{$header{layer}}][ unpack("C",pack("B*","0" x 4 . $header{bitrate})) - 1];
	my $sample	= $samples{$header{version}}{$header{sample}};
	
	my $length = $layer{$header{layer}}
		? (144 * ($bitrate * 1000) / $sample + $header{pad}) #layers 2 & 3
		: ((12 * ($bitrate * 1000) / $sample + $header{pad}) * 4); # layer 1
	
	
	
	read $fh,my($content),$length - 4 - ($header{crc} ? 0 : 2); # appearantly header length is included... learned this the hard way.
	
	my $broken = 0;
	if ((not $header{crc}) and ((not $header{layer}) or $header{layer} eq '01')){
		my $bits = $protbits[$layer{$header{layer}}][ $header{chanmode} eq '11' ? 0 : 1 ];
		my $i;
		
		my $c = 0xffff;
		
		$c = ($c << 8) ^ $crc_table[(($c >> 8) ^ ord((substr($behead,2,1)))) & 0xff];
		$c = ($c << 8) ^ $crc_table[(($c >> 8) ^ ord((substr($behead,3,1)))) & 0xff];
		
		for ($i = 0; $bits >= 32; do { $bits-=32; $i+=4 }){
			my $data = unpack("N",substr($content,$i,4));
			
			$c = ($c << 8) ^ $crc_table[(($c >> 8) ^ ($data >> 24)) & 0xff];
			$c = ($c << 8) ^ $crc_table[(($c >> 8) ^ ($data >> 16)) & 0xff];
			$c = ($c << 8) ^ $crc_table[(($c >> 8) ^ ($data >>  8)) & 0xff];
			$c = ($c << 8) ^ $crc_table[(($c >> 8) ^ ($data >>  0)) & 0xff];
			
		}
		while ($bits >= 8){
			$c = ($c << 8) ^ $crc_table[(($c >> 8) ^ (ord(substr($content,$i++,1)))) & 0xff];
		} continue { $bits -= 8 }
		
		$broken = 1 if ( $c & 0xffff ) != unpack("n",$crc);	
	}
	
	bless {
		header	=> \%header,	# header bits
		content	=> $content,	# the actuaol content of the frame, excluding the header and crc
		length	=> $length,		# the length of the header + content == length($frame->content()) + 4 + ($frame->crc() ? 2 : 0);
		bitrate	=> $bitrate,	# the bitrate, in kilobits
		sample	=> $sample,		# the sample rate, in Hz
		broken	=> $broken,		# wether or not the checksum broke
		offset	=> $offset,		# the offset where the header was found in the handle, based on tell
		binhead	=> $behead,		# binary header data
		crc		=> $crc,
	},$pkg;
}

# methods

sub asbin { $_[0]->header() . ( $_[0]->{header}{crc} ? '' : $_[0]->crc() ) . $_[0]->content() };
sub content { $_[0]{content} }; 	# byte content of frame
sub header { wantarray ? %{ $_[0]{header} } : $_[0]{binhead} };	# header hash folded to array in list context, binary header data in scalar
sub crc	{ $_[0]{crc} };	# the crc
sub length { $_[0]{length} };		# length of frame in bytes
sub bitrate { $_[0]{bitrate} };
sub sample { $_[0]{sample} };		# the sample rate
sub channels { $_[0]{chanmode} };
sub seconds { no integer; $layer{$_[0]{header}{layer}} ? (1152 / $_[0]->sample()) : (384 / $_[0]->sample()) }	# seconds, microseconds || seconds return value
sub framerate { no integer; 1 / $_[0]->seconds() };
sub broken { $_[0]{broken} };		# was the crc broken?
sub pad	{ not not $_[0]{header}{pad} }; # Perl default true is a nicer thing, i guess.
sub offset { $_[0]{offset} }; # the offset

# tie hack

sub TIEHANDLE { bless \$_[1],$_[0] } # encapsulate the handle to save on unblessing and stuff
sub READLINE { (ref $_[0])->read(${$_[0]}) } # read from the encapsulated handle

1; # keep your mother happy

__END__

=pod

=head1 NAME

MPEG::Audio::Frame - a class for weeding out MPEG audio frames out of a file handle.

=head1 SYNOPSIS

	use MPEG::Audio::Frame;

	open FILE,"file.mp3";

        while(my $frame = MPEG::Audio::Frame->read(\*FILE)){
		print $frame->offset(), ": ", $frame->bitrate(), "Kbps/", $frame->sample()/1000, "KHz\n"; # or something.
	}

=head1 DESCRIPTION

A very simple, pure Perl module which allows parsing out data from mp3 files, or streams, and chunking them up into different frames. You can use this to accurately determine the length of an mp3, filter nonaudio data, or chunk up the file for streaming via datagram. Virtually anything is possible.

=head1 METHODS

=over 4

=item read GLOB

This is the constructor method. It receives a reference to a filehandle, and reads the next (hopefully) valid frame it can find on the stream. Please make sure use binmode if you're on a funny platform - the module doesn't know the difference, and shouldn't change stuff, IMHO.

=item asbin

Returns the binary data extracted from the handle. This is (definately|probably) a valid MPEG 1 or 2 audio frame.

asbin is also called via the overloaded operator "", so if you treat the frame object like a string, you'd get the binary data you'd get by calling asbin directly.

=item content

Returns the content of the frame, minus the header and the crc. This is (definately|probably) a valid MPEG 1 or 2 audio frame entity.

=item header

Returns a folded hash in list context, or a 4 byte long binary string in scalar context. The hash represents the header, split into it's parts, with bits translated into '0' and '1'. The binary string is (definately|probably) a valid MPEG 1 or 2 audio frame header.

=item crc

Returns the bytes of the checksum, as extracted from the handle. This is (definately) a valid checksum, unless there was none in the frame, in which case it will be undef. It (definately|probably) applies to the frame.

=item length

Returns the length, in bytes, of the entire frame. This is the length of the content, plus the four bytes of the header, and the two bytes of the crc, if applicable.

=item bitrate

Returns the bitrate in kilobits. Note that 128Kbps means 128000, and not 131072.

=item sample

Returns the sample rate in Hz.

=item seconds

Returns the length, in floating seconds, of the frame.

=item framerate

Should this frame describe the stream, the framerate would be the return value from this method.

=item broken

This returns true if the CRC computation failed for a protected layer I or III frame. It will always return false on unprotected frames.

=item pad

Wether or not the frame was padded.

=item offset

The offset where the frame was found in the handle, as reported by tell().

=back

=head1 TIED HANDLE USAGE

You can also read frame objects via the <HANDLE> operator by tying a filehandle to this package in the following manner:

	tie \*MP3, 'MPEG::Audio::Frame',\*FH;
	while(<MP3>){
		print "frame at ", $_->offset(), "\n";
	}

Way cool.

=head1 HISTORY

=head2 0.06 October 17th 2003

Fixed some doc errors, thanks to Nikolaus Schusser and Suleyman Gulsuner.

Fixed CRC computation on little endian machines.

=head2 0.05 August 3rd 2003

Added overloading of object to asbin by default.

Added real CRC checking for layers III and I (layer II is a longer story).

=head2 0.04 August 2nd 2003

Fixed the calculation of frame lengths when a CRC is present, thanks to Johan Vromans.

=head2 0.03 April 19th 2003

Reimplemented C<offset> method, which came out of sync whilst working on various copies, thanks to Jeff 
Anderson.

=head2 0.02 April 18th 2003

Some minor documentation and distribution fixes were made.

=head1 AUTHOR

Yuval Kojman <nothingmuch@altern.org>

=head1 COPYRIGHT

	Copyright (c) 2003 Yuval Kojman. All rights reserved
	This program is free software; you can redistribute
	it and/or modify it under the same terms as Perl itself.

=cut
