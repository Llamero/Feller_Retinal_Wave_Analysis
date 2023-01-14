close("*");
setBatchMode(true);
run("Bio-Formats Macro Extensions");

dir = getDirectory("Choose the root directory to process");
out_dir = dir;
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
  		//Open full length movie as one stack
		print("---------------------------------------");
		n++;
		print("Processing file " + n + " of " + count);
	  	close("*");
	  	run("Collect Garbage");
	  	print(dir);
	  	file_prefix = replace(file_list[i], "histogram - ", "");
	  	file_prefix = replace(file_prefix, ".tif$", "");
	  	printUpdate("Prefix: " + file_prefix);
	  	print(dir + "dF stack - " + file_prefix + ".tif");
	  	if(File.exists(dir + "dF stack - " + file_prefix + ".tif")){
			processFile(file_prefix, out_dir);
	  	}
	  }       
  }
}

function processFile(file_prefix, out_dir) {
	open(dir + "histogram - " + file_prefix + ".tif");
	rename("histogram");
	Ext.setId(dir + "dF stack - " + file_prefix + ".tif");
	
	//Bin histogram to get integrated area of each wave
	selectWindow("histogram");
//	setOption("BlackBackground", true);
//	setThreshold(0.5, 1e30);
//	run("Convert to Mask", "method=Default background=Dark black");
	Stack.getDimensions(width, height, channels, slices, frames);
	run("Z Project...", "projection=[Sum Slices]");
	selectWindow("SUM_histogram");
	run("Bin...", "x=1 y=" + height + " bin=Sum");
	
	//Find largest wave by area
	id = 1;
	max_id = 0;
	prev_max = 1e30;
	while(id > 0){
		selectWindow("SUM_histogram");
		current_max = -1;
		for(x=1; x<width; x++){
			 value = getPixel(x, 0);
			 if(value > current_max && value < prev_max){
			 	max_id = x;
			 	current_max = value;
			 }
		}
		id = getNumber("Enter wave id (default = next largest wave; 0 = open next file)", max_id);
		if(id < 1) break;
		if(id == max_id) prev_max = current_max;
		selectWindow("SUM_histogram");
		area = getValue(id, 0);
		
		//Find start and end slide of wave
		selectWindow("histogram");
		start_slice = -1;
		end_slice = -1;
		for(slice=1; slice<=slices; slice++){
			setSlice(slice);
			for(y=0; y<height; y++){
				value = getPixel(id, y);
				if(value > 0){
					if(start_slice < 1) start_slice = (slice-1)*height + y + 1;
				}
				else if(start_slice > 0 && end_slice < 1){
					end_slice = (slice-1)*height + y;
					break;
				}
			}
			if(start_slice > 0 && end_slice > 1) break;
		}
		print("ID: " + id + ", Area: " + area + ", Start slice: " + start_slice + ", End slice: " + end_slice);
		//load wave substack
		run("Bio-Formats Importer", "open=[" + dir + "watershed - " + file_prefix + ".tif] autoscale color_mode=Default rois_import=[ROI manager] specify_range view=Hyperstack stack_order=XYCZT z_begin=" + start_slice + " z_end=" + end_slice + " z_step=1");
		selectWindow("watershed - " + file_prefix + ".tif");
		run("Macro...", "code=[if(v==" + id + ") v=1; else v=0;] stack");
		setMinAndMax(0, 1);
		run("8-bit");
		run("Find Edges", "stack");
		run("Bio-Formats Importer", "open=[" + dir + "dF stack - " + file_prefix + ".tif] autoscale color_mode=Default rois_import=[ROI manager] specify_range view=Hyperstack stack_order=XYCZT z_begin=" + start_slice + " z_end=" + end_slice + " z_step=1");
		selectWindow("dF stack - " + file_prefix + ".tif");
		Stack.getStatistics(voxelCount, mean, min, max, stdDev);
		setMinAndMax(min, max);
		run("8-bit");
		run("Merge Channels...", "c2=[dF stack - " + file_prefix + ".tif] c6=[watershed - " + file_prefix + ".tif] create ignore");
		
		//Presetn substack
		selectWindow("Composite");
		run("RGB Color", "slices");
		setBatchMode("show");
		for(slice=1; slice<=nSlices; slice++){
			setSlice(slice);
			wait(50);
		}
		waitForUser("Press ok to check next wave");
		close("Composite");
	}
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

