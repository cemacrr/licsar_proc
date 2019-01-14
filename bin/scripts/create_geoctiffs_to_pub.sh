#!/bin/bash
if [ -z $2 ]; then echo "inputs are: procdir ifg"; exit; fi

#module load LiCSAR/dev

procdir=$1
#master=$2
master=`ls $procdir/geo/*[0-9].hgt | rev | cut -d '/' -f1 | rev | cut -d '.' -f1 | head -n1`
ifg=$2
#publicdir=

echo "Processing dir: $procdir"
echo "Master image: $master"
echo "Interferogram: $ifg"

width=`awk '$1 == "range_samples:" {print $2}' ${procdir}/RSLC/$master/$master.rslc.mli.par`; #echo $width
length=`awk '$1 == "azimuth_lines:" {print $2}' ${procdir}/RSLC/$master/$master.rslc.mli.par`; #echo $length
reducfac=`echo $width | awk '{if(int($1/16000) > 1) print int($1/16000); else print 1}'`

#if [ -d "${procdir}/GEOC" ]; then rm -rf ${procdir}/GEOC; fi
if [ ! -d "${procdir}/GEOC" ]; then mkdir ${procdir}/GEOC; fi

lat=`awk '$1 == "corner_lat:" {print $2}' ${procdir}/geo/EQA.dem_par`
lon=`awk '$1 == "corner_lon:" {print $2}' ${procdir}/geo/EQA.dem_par`
latstep=`awk '$1 == "post_lat:" {print $2}' ${procdir}/geo/EQA.dem_par`
lonstep=`awk '$1 == "post_lon:" {print $2}' ${procdir}/geo/EQA.dem_par`
length_dem=`awk '$1 == "nlines:" {print $2}' ${procdir}/geo/EQA.dem_par`
width_dem=`awk '$1 == "width:" {print $2}' ${procdir}/geo/EQA.dem_par`
reducfac_dem=`echo $width_dem | awk '{if(int($1/2000) > 1) print int($1/2000); else print 1}'`
lat1=`echo $lat $latstep $length_dem | awk '{printf "%7f", ($1+($2*($3-1)));}'` # Substract one because width starts at zero
lon1=`echo $lon $lonstep $width_dem | awk '{printf "%7f", ($1+($2*($3-1)));}'`
latstep=`awk '$1 == "post_lat:" {if($2<0) printf "%7f", -1*$2; else printf "%7f", $2}' ${procdir}/geo/EQA.dem_par`
lonstep=`awk '$1 == "post_lon:" {if($2<0) printf "%7f", -1*$2; else printf "%7f", $2}' ${procdir}/geo/EQA.dem_par`
# Because no wavelength is reported in master.rmli.par file, we calculated here according to the radar frequency (IN CENTIMETERS)
# Frequency = (C / Wavelength), Where: Frequency: Frequency of the wave in hertz (hz). C: Speed of light (29,979,245,800 cm/sec (3 x 10^10 approx))
lambda=`awk '$1 == "radar_frequency:" {print 29979245800/$2}' ${procdir}/RSLC/$master/$master.rslc.mli.par`;

echo " Running doGeocoding step for unwrapped"
logfile=${procdir}/13_doGeocoding.log
echo "   check "$logfile" if something goes wrong "
#rm -f $logfile

#mdate=`echo $ifg | awk '{print $2}'`;
#sdate=`echo $ifg | awk '{print $3}'`;
#if [ -d "${procdir}/GEOC/${ifg}" ]; then rm -rf ${procdir}/GEOC/${ifg}; fi
if [ ! -d "${procdir}/GEOC/${ifg}" ]; then mkdir ${procdir}/GEOC/${ifg}; fi
echo "   Geocoding results for inteferogram: ${ifg}" ;

# Unwrapped interferogram
if [ -e ${procdir}/IFG/${ifg}/${ifg}.unw ]; then
  # Geocode all the data
  if [ ! -e ${procdir}/GEOC/${ifg}/${ifg}.geo.unw ]; then
  echo "Replacing nan for 0 values (trick by Yu Morishita)"
   #I will correct nan-corrected unwrapped ifg here and then convert the unwrapped phase to metric units
   replace_values ${procdir}/IFG/${ifg}/${ifg}.unw nan 0 ${procdir}/IFG/${ifg}/${ifg}.unw0 $width >> $logfile
   if [ `ls -al ${procdir}/IFG/${ifg}/${ifg}.unw  | gawk {'print $5'}` -eq  `ls -al ${procdir}/IFG/${ifg}/${ifg}.unw0  | gawk {'print $5'}` ]; then
     mv ${procdir}/IFG/${ifg}/${ifg}.unw0 ${procdir}/IFG/${ifg}/${ifg}.unw
   else
     rm ${procdir}/IFG/${ifg}/${ifg}.unw0 
   fi
  echo "Converting unwrapped phase to displacements"
   dispmap ${procdir}/IFG/${ifg}/${ifg}.unw ${procdir}/geo/$master.hgt ${procdir}/SLC/$master/$master.slc.par ${procdir}/IFG/${ifg}/${ifg}.off ${procdir}/IFG/${ifg}/${ifg}.disp 0 0 >> $logfile
   #mv ${procdir}/IFG/${ifg}/${ifg}.disp ${procdir}/IFG/${ifg}/${ifg}.unw
  echo "Geocoding"
   geocode_back ${procdir}/IFG/${ifg}/${ifg}.unw $width ${procdir}/geo/$master.lt_fine ${procdir}/GEOC/${ifg}/${ifg}.geo.unw ${width_dem} ${length_dem} 0 0 >> $logfile
   geocode_back ${procdir}/IFG/${ifg}/${ifg}.disp $width ${procdir}/geo/$master.lt_fine ${procdir}/GEOC/${ifg}/${ifg}.geo.disp ${width_dem} ${length_dem} 0 0 >> $logfile
  fi
  # Convert to geotiff
  if [ ! -e ${procdir}/GEOC/${ifg}/${ifg}.geo.unw.tif ]; then 
   echo "Converting to GeoTIFF"
   data2geotiff ${procdir}/geo/EQA.dem_par ${procdir}/GEOC/${ifg}/${ifg}.geo.unw 2 ${procdir}/GEOC/${ifg}/${ifg}.geo.unw.tif 0.0  >> $logfile
   data2geotiff ${procdir}/geo/EQA.dem_par ${procdir}/GEOC/${ifg}/${ifg}.geo.disp 2 ${procdir}/GEOC/${ifg}/${ifg}.geo.disp.tif 0.0  >> $logfile
  fi
  # Create bmps
  #ras_linear ${procdir}/GEOC/${ifg}/${ifg}.geo.unw ${width_dem} - - $reducfac_dem $reducfac_dem - - - ${procdir}/GEOC/${ifg}/${ifg}.geo.unw.bmp >> $logfile
  if [ ! -e ${procdir}/GEOC/${ifg}/${ifg}.geo.unw_blk.bmp ]; then
   echo "Converting to raster previews"
   rasrmg ${procdir}/GEOC/${ifg}/${ifg}.geo.unw ${procdir}/geo/EQA.${master}.slc.mli ${width_dem} - - - $reducfac_dem $reducfac_dem - - - - - ${procdir}/GEOC/${ifg}/${ifg}.geo.unw_blk.bmp >> $logfile
   #rasrmg ${procdir}/GEOC/${ifg}/${ifg}.geo.disp ${procdir}/geo/EQA.${master}.slc.mli ${width_dem} - - - $reducfac_dem $reducfac_dem - - - - - ${procdir}/GEOC/${ifg}/${ifg}.geo.disp_blk.bmp >> $logfile
   #get min and max for disp image
   gdalinfo -stats ${procdir}/GEOC/${ifg}/${ifg}.geo.disp.tif > ${procdir}/GEOC/${ifg}/${ifg}.geo.disp.stats
   min=`grep MINIMUM ${procdir}/GEOC/${ifg}/${ifg}.geo.disp.stats | cut -d '=' -f2`
   max=`grep MAXIMUM ${procdir}/GEOC/${ifg}/${ifg}.geo.disp.stats | cut -d '=' -f2`
   std=`grep STDDEV ${procdir}/GEOC/${ifg}/${ifg}.geo.disp.stats | cut -d '=' -f2`
   max=`echo $max-$std | bc`
   min=`echo $min+$std | bc`
   #generate displacement image
   visdt_pwr.py ${procdir}/GEOC/${ifg}/${ifg}.geo.disp ${procdir}/geo/EQA.${master}.slc.mli ${width_dem} $min $max -b -p ${procdir}/GEOC/${ifg}/${ifg}.geo.disp_blk.png >> $logfile
   #rasdt_cmap ${procdir}/GEOC/${ifg}/${ifg}.geo.disp ${procdir}/geo/EQA.${master}.slc.mli ${width_dem} - - - $reducfac_dem $reducfac_dem $min $max 0 - - - ${procdir}/GEOC/${ifg}/${ifg}.geo.disp_blk.bmp >> $logfile
  fi
  if [ ! -e ${procdir}/GEOC/${ifg}/${ifg}.geo.unw.bmp ]; then
   convert -transparent black -resize 30% ${procdir}/GEOC/${ifg}/${ifg}.geo.unw_blk.bmp ${procdir}/GEOC/${ifg}/${ifg}.geo.unw.bmp
   #convert -transparent black -resize 30% ${procdir}/GEOC/${ifg}/${ifg}.geo.disp_blk.bmp ${procdir}/GEOC/${ifg}/${ifg}.geo.disp.bmp
  fi
fi

#Filtered interferograms... also is in this public LiCSAR website...
if [ -e ${procdir}/IFG/${ifg}/${ifg}.filt.diff ] && [ ! -e ${procdir}/GEOC/${ifg}/${ifg}.geo.diff.bmp ]; then
 echo "Creating filtered interferogram tiffs"
 # Extract the mag and phase
 cpx_to_real ${procdir}/IFG/${ifg}/${ifg}.filt.diff ${procdir}/IFG/${ifg}/${ifg}.diff_mag $width 3  >> $logfile
 cpx_to_real ${procdir}/IFG/${ifg}/${ifg}.filt.diff ${procdir}/IFG/${ifg}/${ifg}.diff_pha $width 4  >> $logfile
 # Geocode all the data
 geocode_back ${procdir}/IFG/${ifg}/${ifg}.filt.diff $width ${procdir}/geo/$master.lt_fine ${procdir}/GEOC/${ifg}/${ifg}.geo.diff ${width_dem} ${length_dem} 1 1 >> $logfile
 geocode_back ${procdir}/IFG/${ifg}/${ifg}.diff_mag $width ${procdir}/geo/$master.lt_fine ${procdir}/GEOC/${ifg}/${ifg}.geo.diff_mag ${width_dem} ${length_dem} 1 0 >> $logfile
 geocode_back ${procdir}/IFG/${ifg}/${ifg}.diff_pha $width ${procdir}/geo/$master.lt_fine ${procdir}/GEOC/${ifg}/${ifg}.geo.diff_pha ${width_dem} ${length_dem} 0 0 >> $logfile
 # Convert to geotiff
 data2geotiff ${procdir}/geo/EQA.dem_par ${procdir}/GEOC/${ifg}/${ifg}.geo.diff_mag 2 ${procdir}/GEOC/${ifg}/${ifg}.geo.diff_mag.tif 0.0  >> $logfile
 data2geotiff ${procdir}/geo/EQA.dem_par ${procdir}/GEOC/${ifg}/${ifg}.geo.diff_pha 2 ${procdir}/GEOC/${ifg}/${ifg}.geo.diff_pha.tif 0.0  >> $logfile
 # Create bmps
 rasmph_pwr ${procdir}/GEOC/${ifg}/${ifg}.geo.diff ${procdir}/geo/EQA.${master}.slc.mli ${width_dem} - - - $reducfac_dem $reducfac_dem - - - ${procdir}/GEOC/${ifg}/${ifg}.geo.diff_blk.bmp >> $logfile
 convert -transparent black -resize 30% ${procdir}/GEOC/${ifg}/${ifg}.geo.diff_blk.bmp ${procdir}/GEOC/${ifg}/${ifg}.geo.diff.bmp
 #rasmph_pwr ${procdir}/GEOC/${ifg}/${ifg}.geo.diff_mag ${procdir}/geo/EQA.${master}.slc.mli ${width_dem} - - - $reducfac_dem $reducfac_dem - - - ${procdir}/GEOC/${ifg}/${ifg}.geo.diff_mag.bmp >> $logfile
 #rasmph_pwr ${procdir}/GEOC/${ifg}/${ifg}.geo.diff_pha ${procdir}/geo/EQA.${master}.slc.mli ${width_dem} - - - $reducfac_dem $reducfac_dem - - - ${procdir}/GEOC/${ifg}/${ifg}.geo.diff_pha.bmp >> $logfile

 #This was to generate only mag and pha bmp..
 #raspwr ${procdir}/GEOC/${ifg}/${ifg}.geo.diff_mag ${width_dem} - - $reducfac_dem $reducfac_dem - - - ${procdir}/GEOC/${ifg}/${ifg}.geo.diff_mag.bmp >> $logfile
 #ras_linear ${procdir}/GEOC/${ifg}/${ifg}.geo.diff_pha ${width_dem} - - $reducfac_dem $reducfac_dem - - - ${procdir}/GEOC/${ifg}/${ifg}.geo.diff_pha.bmp >> $logfile
 # Clean
 rm ${procdir}/IFG/${ifg}/${ifg}.diff_mag ${procdir}/IFG/${ifg}/${ifg}.diff_pha
fi

# Filtered coherence
if [ -e ${procdir}/IFG/${ifg}/${ifg}.filt.cc ] && [ ! -e ${procdir}/GEOC/${ifg}/${ifg}.geo.cc.bmp ]; then
  echo "Creating filtered coherence tiffs"
  # Geocode
  geocode_back ${procdir}/IFG/${ifg}/${ifg}.filt.cc $width ${procdir}/geo/$master.lt_fine ${procdir}/GEOC/${ifg}/${ifg}.geo.cc ${width_dem} ${length_dem} 1 0 >> $logfile
  # Convert to geotiff
  data2geotiff ${procdir}/geo/EQA.dem_par ${procdir}/GEOC/${ifg}/${ifg}.geo.cc 2 ${procdir}/GEOC/${ifg}/${ifg}.geo.cc.tif 0.0  >> $logfile
  # create bmps
  rascc ${procdir}/GEOC/${ifg}/${ifg}.geo.cc - ${width_dem} - - - $reducfac_dem $reducfac_dem 0 1 - - - ${procdir}/GEOC/${ifg}/${ifg}.geo.cc_blk.bmp >> $logfile
  # Need to remove the black border, but the command below is no good as it removes the black parts of the coherence!
  #convert -transparent black -resize 30% ${procdir}/GEOC/${ifg}/${ifg}.geo.cc_blk.bmp ${procdir}/GEOC/${ifg}/${ifg}.geo.cc.bmp
  convert -resize 30% ${procdir}/GEOC/${ifg}/${ifg}.geo.cc_blk.bmp ${procdir}/GEOC/${ifg}/${ifg}.geo.cc.bmp
fi
echo "done"

#Move it to the public area(?)
#for filename in .......; do
# if [ ! -f ${publicdir}/ ]
