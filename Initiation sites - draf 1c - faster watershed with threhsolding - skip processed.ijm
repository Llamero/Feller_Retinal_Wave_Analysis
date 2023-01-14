close("*");
setBatchMode(true);

dF_blur = 0.8 //2D blur to apply to df to smooth/denoise cell transients
min_duration = 15; //Remove dF objects that have a duration shorter than a single cell wave transient (30 slices)
min_area = 9*min_duration; //Min total area of a wave (single cell = 9 pixels);
initiation_slices = 30; //Number of slices to look for initiation site
results_image_rows = 7; //Number of rows (measurements) in the results image

dir = getDirectory("Choose the root directory to process");
out_dir = dir;
root_dir = dir;
count = 0;
countFiles(dir, out_dir);
print(count);
n = 0;
processFiles(dir, out_dir);

function countFiles(dir, out_dir) {
  list = getFileList(dir);
  File.makeDirectory(out_dir);
  for (i=0; i<list.length; i++) {
      if (endsWith(list[i], "/"))
      	countFiles(""+dir+list[i], ""+out_dir+list[i]);
      else if(startsWith(list[i], "watershed - ")){
  		count++;
      } 	
  }
}

function processFiles(dir, out_dir) {
    file_list = getFileList(dir);
	for (i=0; i<file_list.length; i++) {
	  if(endsWith(file_list[i], "/"))
	      processFiles(""+dir+file_list[i], ""+out_dir+file_list[i]);
	  else if(startsWith(file_list[i], "histogram - ") && endsWith(file_list[i], "tif")){
  		print("\\Clear"); //Clear log file
  		//Open full length movie as one stack
		print("---------------------------------------");
		n++;
		print("Processing file " + n + " of " + count);
	  	close("*");
	  	wait(5000);
	  	run("Collect Garbage");
	  	print(dir);
	  	file_prefix = replace(file_list[i], "histogram - ", "");
	  	file_prefix = replace(file_prefix, ".tif$", "");
	  	printUpdate("Prefix: " + file_prefix);
	  	print(dir + "dF stack - " + file_prefix + ".tif");
	  	if(File.exists(dir + "dF stack - " + file_prefix + ".tif")){
	  		if(File.exists(dir + "initiation sites - " + file_prefix + ".tif")) print("Skipped: " + file_prefix + ", already processed");
			else processFile(file_prefix, out_dir);
	  	}
	  }       
  }
}

function processFile(file_prefix, out_dir) {
	open(dir + "histogram - " + file_prefix + ".tif");
	rename("histogram");
	Stack.getDimensions(hist_width, hist_height, dummy, hist_slices, dummy);
	binHistogram();
	
	skipped_wave_counter = 0;
	for(id=1; id<hist_width; id++){
		selectWindow("area");
		area = getPixel(id, 0);
		selectWindow("duration");
		duration = getPixel(id, 0);
		if(area >= min_area && duration >= min_duration){
			findInitiationSites(id);
		}
		else skipped_wave_counter++;
	}
	selectWindow("initiation sites");
	saveAs("Tiff", out_dir + "initiation sites - " + file_prefix + ".tif");
	print(skipped_wave_counter + " waves skipped of " + hist_width); 
	close("*");
	wait(5000);
	run("Collect Garbage");
}

function binHistogram(){
	function bin(i){
		selectWindow(i);
		run("Z Project...", "projection=[Sum Slices]");
		selectWindow("SUM_" + i);
		run("Bin...", "x=1 y=" + hist_height + " bin=Sum");
		close(i);
		selectWindow("SUM_" + i);
		rename(i);
	}
	//Get total area per wave
	selectWindow("histogram");
	run("Duplicate...", "title=[area] duplicate");
	bin("area");
	
	//Get total duration per wave
	selectWindow("histogram");
	run("Duplicate...", "title=[duration] duplicate");
	selectWindow("duration");
	setOption("BlackBackground", true);
	setThreshold(0.5, 1e30);
	run("Convert to Mask", "method=Default background=Dark black");
	run("Divide...", "value=255 stack");
	bin("duration");
	
	//Create image to store positions of initiation sites
	selectWindow("area");
	run("Duplicate...", "title=1");
	selectWindow("duration");
	run("Duplicate...", "title=2");
	run("Combine...", "stack1=1 stack2=2 combine");
	selectWindow("Combined Stacks");
	rename("initiation sites");
	run("Canvas Size...", "width=" + hist_width + " height=" + results_image_rows + " position=Top-Center zero");
}

function findInitiationSites(id){
	//Find start and end slide of wave
	selectWindow("histogram");
	start_slice = -1;
	end_slice = -1;

	for(slice=1; slice<=hist_slices; slice++){
		setSlice(slice);
		for(y=0; y<hist_height; y++){
			value = getPixel(id, y);
			if(value > 0){
				if(start_slice < 1) start_slice = (slice-1)*hist_height + y + 1;
			}
			else if(start_slice > 0 && end_slice < 1){
				end_slice = (slice-1)*hist_height + y;
				break;
			}
		}
		if(start_slice > 0 && end_slice > 1) break;
	}

	//load wave substacks
	run("Bio-Formats Importer", "open=[" + dir + "dF stack - " + file_prefix + ".tif] autoscale color_mode=Default rois_import=[ROI manager] specify_range view=Hyperstack stack_order=XYCZT z_begin=" + start_slice + " z_end=" + end_slice + " z_step=1");
	run("Properties...", "channels=1 slices=" + nSlices + " frames=1 pixel_width=1 pixel_height=1 voxel_depth=1 global");
	selectWindow("dF stack - " + file_prefix + ".tif");
	run("Gaussian Blur...", "sigma=" + dF_blur + " stack"); //Match original segmentation blur
	rename("dF");
	run("Bio-Formats Importer", "open=[" + dir + "watershed - " + file_prefix + ".tif] autoscale color_mode=Default rois_import=[ROI manager] specify_range view=Hyperstack stack_order=XYCZT z_begin=" + start_slice + " z_end=" + end_slice + " z_step=1");

	//Segment initiation sites
	selectWindow("watershed - " + file_prefix + ".tif");
	int = 1;
	setThreshold(id, id);
	for(a=nSlices; a>0; a--){
		Stack.setSlice(a);
//		run("Macro...", "code=[if(v==" + id + ") v=" + int + "; else v=0;] slice");
		run("Create Selection");
		run("Set...", "value=" + int + " slice");
		run("Make Inverse");
		run("Set...", "value=0 slice");
		run("Select None");
		int++;
	}
	resetMinAndMax();
	run("Invert", "stack");
	run("Classic Watershed", "input=[watershed - " + file_prefix + ".tif] mask=None use min=0 max=" + nSlices-1);
	close("watershed - " + file_prefix + ".tif");
	if(isOpen("watershed")){
		selectWindow("watershed");
		Stack.getStatistics(dummy,dummy,dummy, n_sites, dummy);
	}
	else{
		n_sites = 0;
		print("ERROR: WATERSHED FAILED!");
	}
	printUpdate("ID: " + id + " of " + hist_width + ", Area: " + area + ", Start slice: " + start_slice + ", End slice: " + end_slice + ", # Initiation sites: "  + n_sites);

	
	//Append slices to resolts stack if needed
	selectWindow("initiation sites");
	while(nSlices < n_sites){
		setSlice(nSlices);
		run("Add Slice");
	}
	
	//Find the initiation sites for each subwave
	for(initiation_id = 1; initiation_id <= n_sites; initiation_id++){
		selectWindow("watershed");
		run("Duplicate...", "title=" + initiation_id + " duplicate");
		selectWindow(toString(initiation_id, 0));
		setThreshold(initiation_id-0.1, initiation_id+0.1);
		run("Convert to Mask", "method=Default background=Dark black");
		
		//Find the start of the sub-wave
		for(slice = 1; slice<=nSlices; slice++){
			setSlice(slice);
			getStatistics(dummy, dummy, dummy, max);
			if(max > 0) break;
		}
		
		//Find position of initiation site
		selectWindow(toString(initiation_id, 0));
		run("Duplicate...", "title=initiation_mask duplicate range=" + slice + "-" + slice);
		run("Divide...", "value=255.000");
		selectWindow("dF");
		run("Duplicate...", "title=initiation_df duplicate range=" + slice + "-" + slice);
		imageCalculator("Multiply", "initiation_df","initiation_mask");
		selectWindow("initiation_df");
		setThreshold(0.01, 1e30);
		run("Create Selection");
		List.setMeasurements;
		x = List.getValue("X");
		y = List.getValue("Y");
		xm = List.getValue("XM");
		ym = List.getValue("YM");
		start = start_slice + slice - 1;
		
		selectWindow("initiation sites");
		setSlice(initiation_id);
		setPixel(id, 2, start);
		setPixel(id, 3, x);
		setPixel(id, 4, y);
		setPixel(id, 5, xm);
		setPixel(id, 6, ym);
		close("initiation_dF");
		
		//Find distance and time to previous initiation site
		if(isOpen("prev sites")){
			//distance
			selectWindow("prev sites");
			run("Duplicate...", "title=ref duplicate range=" + slice + "-" + slice);
			selectWindow("ref");
			run("Invert", "stack");
			run("Exact Euclidean Distance Transform (3D)");
			selectWindow("initiation_mask");
			setThreshold(0.5, 1e30);
			run("Create Selection");
			selectWindow("EDT");
			run("Restore Selection");		
			getStatistics(dummy, dummy, min_distance);
			close("EDT");
			close("initiation_mask");
			close("ref");

			//time
			selectWindow(toString(initiation_id, 0));
			run("Duplicate...", "title=mask duplicate");
			selectWindow("mask");
			run("Dilate", "stack");
			run("Dilate", "stack");
			imageCalculator("AND stack", "mask","prev sites");
			prominence = -1;
			for(start=slice; start<=nSlices; start++){
				setSlice(start);
				getStatistics(area, mean);
				if(mean > 0) prominence = start-slice;
			}
			
			selectWindow("initiation sites");
			setSlice(initiation_id);
			setPixel(id, 0, min_distance);
			setPixel(id, 1, prominence);
			
			//Add wave to prev sites stack
			imageCalculator("OR stack", "prev sites", toString(initiation_id, 0));
			close(toString(initiation_id, 0));
			close("mask");
		}
		else if(n_sites > 1){
			selectWindow(toString(initiation_id, 0));
			rename("prev sites");
		}
		print(toString(initiation_id, 0));
		selectWindow("Log");
		saveAs("Text", out_dir + "Initiation site log - " + file_prefix + ".txt");
		while(isOpen(toString(initiation_id, 0))) close(toString(initiation_id, 0));
		while(isOpen("initiation_mask")) close("initiation_mask");	
	}
	while(isOpen("watershed")) close("watershed");
	while(isOpen("dF")) close("dF");
	while(isOpen("prev sites")) close("prev sites");
}

function printUpdate(message){ //https://imagej.nih.gov/ij/macros/GetDateAndTime.txt
	MonthNames = newArray("Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec");
	DayNames = newArray("Sun", "Mon","Tue","Wed","Thu","Fri","Sat");
	getDateAndTime(year, month, dayOfWeek, dayOfMonth, hour, minute, second, msec);
	TimeString ="Date: "+DayNames[dayOfWeek]+" ";
	if (dayOfMonth<10) {TimeString = TimeString+"0";}
	TimeString = TimeString+dayOfMonth+"-"+MonthNames[month]+"-"+year+"\nTime: ";
	if (hour<10) {TimeString = TimeString+"0";}
	TimeString = TimeString+hour+":";
	if (minute<10) {TimeString = TimeString+"0";}
	TimeString = TimeString+minute+":";
	if (second<10) {TimeString = TimeString+"0";}
	TimeString = TimeString+second;
	print(TimeString +  " - " + message);
}

setBatchMode("exit and display");

