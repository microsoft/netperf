
export default function accessData(envStr, data, newKey, oldKey) {
    const HISTORY_SIZE = 20;
    if (!(envStr in data)) {
      // alert(`Could not find ${envStr} in data`);
      console.error(`Could not find ${envStr} in data`);
      return [];
    }
    const envData = data[envStr];
    let outputData = [];
    if (oldKey in envData) {
      outputData = envData[oldKey].data.slice().reverse();
    } else {
      console.log("OLD KEY DOES NOT EXIST", oldKey);
    }
    if (newKey in envData) {
      outputData = outputData.concat(envData[newKey].data.slice().reverse());
    } else {
      console.log("NEW KEY DOES NOT EXIST", newKey);
    }
    while (outputData.length > HISTORY_SIZE) {
      outputData.shift();
    }
    return outputData;
  }
