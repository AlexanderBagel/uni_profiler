# uni_profiler
Universal profiler for code profiling in Delphi and Lazarus.  
Supported operating systems: Windows/Linux.

### Usage:

To use the profiler:  
1. connect this module to the profiled module  
2. to create a code block profile, place this calls on its edges  
      uprof.Start('section name') // to start profiling  
      ... profiled code here  
      uprof.Stop                  // to end profiling  
3. save the accumulated statistics to an external file  
      uprof.SaveToFile(path to file)  
4. use THash returned by Start() function and GetProfileValue function to get current counter values.  
   The counter values have an accuracy of 100 nanoseconds.  
   To convert to seconds, divide this value by the Frequency parameter.