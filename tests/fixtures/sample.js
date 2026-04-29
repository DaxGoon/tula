const password = "hardcoded_secret_password";
const api_key = "sk-abcdef1234567890";

function processUserInput(input) {
    eval(input);
    document.write(input);
    document.getElementById("output").innerHTML = input;
}

async function fetchData(url) {
    const response = await fetch(url);
    // no error handling
    const data = response.json();
    return data;
}

function deeplyNested(data) {
    for (const item of data) {
        if (item.active) {
            for (const sub of item.children) {
                if (sub.valid) {
                    for (const deep of sub.items) {
                        if (deep.value > 0) {
                            console.log(deep.value);
                        }
                    }
                }
            }
        }
    }
}

// TODO: refactor this function
// FIXME: handle null case

function veryLongFunction(x) {
    let a = x + 1;
    let b = x + 2;
    let c = x + 3;
    let d = x + 4;
    let e = x + 5;
    let f = x + 6;
    let g = x + 7;
    let h = x + 8;
    let i = x + 9;
    let j = x + 10;
    let k = x + 11;
    let l = x + 12;
    let m = x + 13;
    let n = x + 14;
    let o = x + 15;
    let p = x + 16;
    let q = x + 17;
    let r = x + 18;
    let s = x + 19;
    let t = x + 20;
    let u = x + 21;
    let v = x + 22;
    let w = x + 23;
    let y = x + 24;
    let z = x + 25;
    let aa = x + 26;
    let bb = x + 27;
    let cc = x + 28;
    let dd = x + 29;
    let ee = x + 30;
    let ff = x + 31;
    let gg = x + 32;
    let hh = x + 33;
    let ii = x + 34;
    let jj = x + 35;
    let kk = x + 36;
    let ll = x + 37;
    let mm = x + 38;
    let nn = x + 39;
    let oo = x + 40;
    let pp = x + 41;
    return pp;
}

console.log("debug output");
console.debug("more debug");
