#!/usr/bin/perl

package MPEG::Audio::Frame;

use strict;
use warnings;
use integer;

our $VERSION = 0.03;

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
	
	return undef unless $ok;
	
	my $crc;
	read $fh,$crc,2 unless $header{crc}; # checksum bits
	
	my $bitrate	= $bitrates[$version{$header{version}}][$layer{$header{layer}}][ unpack("C",pack("B*","0" x 4 . $header{bitrate})) - 1];
	my $sample	= $samples{$header{version}}{$header{sample}};
	
	my $length = $layer{$header{layer}}
		? (144 * ($bitrate * 1000) / $sample + $header{pad}) #layers 2 & 3
		: ((12 * ($bitrate * 1000) / $sample + $header{pad}) * 4); # layer 1
	
	
	
	read $fh,my($content),$length-4; # appearantly header length is included... learned this the hard way.
	
	my $broken = 0; # $broken = (unpack("%16S*",$content) == unpack("S" # or is it "s"? # , $crc)) ? 0 : 1; # not enough info in docs. 
	
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

sub asbin { $_[0]->header() . ($_[0]->crc() || '') . $_[0]->content() };
sub content { $_[0]{content} }; 	# byte content of frame
sub header { wantarray ? %{ $_[0]{header} } : $_[0]{binhead} };	# header hash folded to array in list context, binary header data in scalar
sub crc	{ $_[0]{crc} };	# the crc
sub length { $_[0]{length} };		# length of frame in bytes
sub bitrate { $_[0]{bitrate} };
sub sample { $_[0]{sample} };		# the sample rate
sub seconds { no integer; $layer{$_[0]{header}{layer}} ? (1152 / $_[0]->sample()) : (384 / $_[0]->sample()) }	# seconds, microseconds || seconds return value
sub framerate { no integer; 1 / $_[0]->seconds() };
sub broken { $_[0]{broken} };		# was the sum broken?
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

	while(my $frame = MPEG::Audio::Frame->read(\*FILE)){=
		print $frame->offset(), ": ", $frame->bitrate(), "Kbps/", $bitrate->sample()/1000, "KHz\n"; # or something.
	}

=head1 DESCRIPTION

A very simple, pure Perl module which allows parsing out data from mp3 files, or streams, and chunking them up into different frames. You can use this to accurately determine the length of an mp3, filter nonaudio data, or chunk up the file for streaming via datagram. Virtually anything is possible.

=head1 METHODS

=over 4

=item read GLOB

This is the constructor method. It receives a reference to a filehandle, and reads the next (hopefully) valid frame it can find on the stream, 

=item asbin

Returns the binary data extracted from the handle. This is (definately|probably) a valid MPEG 1 or 2 audio frame.

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

This would, had it been implemented, report wether or not the crc of the frame is valid. Since it's not documented thoroughly, and I don't know how to make my encoders add a sum to frames it doesn't. Patches would be greatly appreciated.

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
