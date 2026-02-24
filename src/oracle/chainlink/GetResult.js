// 1. Import ethers
const { ethers } = await import("npm:ethers@6.10.0");

const questionId = args[0];

const apiUrl = `https://oracle-silk.vercel.app/api/results/${questionId}`;

const apiResponse = await Functions.makeHttpRequest({
  url: apiUrl,
});

if (apiResponse.error) {
  throw Error("Request failed");
}

const { data } = apiResponse;

// 2. Extract the array directly
// Assumption: data.result is [0, 1]
const resultArray = data.result;

if (!Array.isArray(resultArray)) {
  throw Error("API did not return an array");
}

// 3. Encode the Array
const abiCoder = ethers.AbiCoder.defaultAbiCoder();

// We are encoding a "uint256[]".
// The second argument must be a list of values.
// Since our value IS an array, we must wrap it: [ resultArray ]
const encoded = abiCoder.encode(["uint256[]"], [resultArray]);

// 4. Return bytes
return ethers.getBytes(encoded);
