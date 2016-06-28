/**
 sprintf() for JavaScript 0.6

 Copyright (c) Alexandru Marasteanu <alexaholic [at) gmail (dot] com>
 All rights reserved.

 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions are met:
 * Redistributions of source code must retain the above copyright
 notice, this list of conditions and the following disclaimer.
 * Redistributions in binary form must reproduce the above copyright
 notice, this list of conditions and the following disclaimer in the
 documentation and/or other materials provided with the distribution.
 * Neither the name of sprintf() for JavaScript nor the
 names of its contributors may be used to endorse or promote products
 derived from this software without specific prior written permission.

 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 DISCLAIMED. IN NO EVENT SHALL Alexandru Marasteanu BE LIABLE FOR ANY
 DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.


 Changelog:
 2007.04.03 - 0.1:
 - initial release
 2007.09.11 - 0.2:
 - feature: added argument swapping
 2007.09.17 - 0.3:
 - bug fix: no longer throws exception on empty paramenters (Hans Pufal)
 2007.10.21 - 0.4:
 - unit test and patch (David Baird)
 2010.05.09 - 0.5:
 - bug fix: 0 is now preceeded with a + sign
 - bug fix: the sign was not at the right position on padded results (Kamal Abdali)
 - switched from GPL to BSD license
 2010.05.22 - 0.6:
 - reverted to 0.4 and fixed the bug regarding the sign of the number 0
 Note:
 Thanks to Raphael Pigulla <raph (at] n3rd [dot) org> (http://www.n3rd.org/)
 who warned me about a bug in 0.5, I discovered that the last update was
 a regress. I appologize for that.
 **/
function str_repeat(e,t){for(var r=[];t>0;r[--t]=e);return r.join("")}function sprintf(){for(var e,t,r,a,s,n=0,o=arguments[n++],i=[],u="";o;){if(t=/^[^\x25]+/.exec(o))i.push(t[0]);else if(t=/^\x25{2}/.exec(o))i.push("%");else{if(!(t=/^\x25(?:(\d+)\$)?(\+)?(0|'[^$])?(-)?(\d+)?(?:\.(\d+))?([b-fosuxX])/.exec(o)))throw"Huh ?!";if(null==(e=arguments[t[1]||n++])||void 0==e)throw"Too few arguments.";if(/[^s]/.test(t[7])&&"number"!=typeof e)throw"Expecting number but found "+typeof e;switch(t[7]){case"b":e=e.toString(2);break;case"c":e=String.fromCharCode(e);break;case"d":e=parseInt(e);break;case"e":e=t[6]?e.toExponential(t[6]):e.toExponential();break;case"f":e=t[6]?parseFloat(e).toFixed(t[6]):parseFloat(e);break;case"o":e=e.toString(8);break;case"s":e=(e=String(e))&&t[6]?e.substring(0,t[6]):e;break;case"u":e=Math.abs(e);break;case"x":e=e.toString(16);break;case"X":e=e.toString(16).toUpperCase()}e=/[def]/.test(t[7])&&t[2]&&e>=0?"+"+e:e,a=t[3]?"0"==t[3]?"0":t[3].charAt(1):" ",s=t[5]-String(e).length-u.length,r=t[5]?str_repeat(a,s):"",i.push(u+(t[4]?e+r:r+e))}o=o.substring(t[0].length)}return i.join("")}