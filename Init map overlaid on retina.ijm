close("*");
setBatchMode(true);

max_exp = 2 //2D max filter used to increase size of initiation sites

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
      else if(startsWith(list[i], "initiation site plot - ")){
  		count++;
      } 	
  }
}

function processFiles(dir, out_dir) {
    file_list = getFileList(dir);
	for (i=0; i<file_list.length; i++) {
	  if(endsWith(file_list[i], "/"))
	      processFiles(""+dir+file_list[i], ""+out_dir+file_list[i]);
	  else if(startsWith(file_list[i], "initiation site plot - ") && endsWith(file_list[i], "tif")){
  		print("\\Clear"); //Clear log file
  		//Open full length movie as one stack
		print("---------------------------------------");
		n++;
		print("Processing file " + n + " of " + count);
	  	close("*");
	  	print(dir);
	  	file_prefix = replace(file_list[i], "initiation site plot - ", "");
	  	file_prefix = replace(file_prefix, ".tif$", "");
	  	printUpdate("Prefix: " + file_prefix);
	  	if(File.exists(dir + "Retina ref - " + file_prefix + ".tif")){
	  		if(File.exists(dir + "initiation site plot with retina - " + file_prefix + ".tif") && File.exists(dir + "dF stdev - " + file_prefix + ".tif")) print("Skipped: " + file_prefix + ", already processed");
			else processFile(file_prefix, out_dir); 
	  	}
	  }       
  }
}

function processFile(file_prefix, out_dir) {
	open(dir + "initiation site plot - " + file_prefix + ".tif");
	selectWindow("initiation site plot - " + file_prefix + ".tif");
	rename("init");
	open(dir + "Retina ref - " + file_prefix + ".tif");
	selectWindow("Retina ref - " + file_prefix + ".tif");
	rename("ref");
	selectWindow("init");
	run("Split Channels");
	close("C2-init");
	selectWindow("C1-init");
	rename("init");
	run("Maximum...", "radius=" + max_exp + " stack");
	Stack.getDimensions(width, height, channels, slices, frames);
	for(s=1; s<=slices*frames; s++){
		selectWindow("ref");
		if(isOpen("ref stack")){
			run("Duplicate...", "title=[ref 1] duplicate");
			run("Concatenate...", "  title=[ref stack] open image1=[ref stack] image2=[ref 1] image3=[-- None --]");
		}
		else{
			run("Duplicate...", "title=[ref stack] duplicate");
		}
	}
	close("ref");
	selectWindow("ref stack");
	run("Hyperstack to Stack");
	run("Stack to Hyperstack...", "order=xyczt(default) channels=2 slices=" + slices + " frames=" + frames + " display=Composite");
	run("Split Channels");
	selectWindow("C1-ref stack");
	run("Merge Channels...", "c1=[init] c2=[C1-ref stack] c3=[C2-ref stack] create ignore");
	selectWindow("Merged");
	for(a=1; a<=3; a++){
		Stack.setChannel(a);
		resetMinAndMax();
	}
	Stack.setChannel(1);
	run("Orange Hot");
	
	selectWindow("Merged");
	saveAs("Tiff", out_dir + "initiation site plot with retina - " + file_prefix + ".tif");
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