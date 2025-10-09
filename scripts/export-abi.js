const fs = require('fs');
const path = require('path');

// Read the compiled contract artifact
const artifactPath = path.join(__dirname, '../artifacts/contracts/spAVAX.sol/spAVAX.json');
const artifact = JSON.parse(fs.readFileSync(artifactPath, 'utf8'));

// Extract just the ABI
const abi = artifact.abi;

// Format for TypeScript
const tsContent = `// Auto-generated ABI for spAVAX contract
// Proxy Address (Fuji): 0xd5be2F451C0B1B8cA17Cc64a1f904405B8120c9B
// Implementation: 0x83807684425B665feE021bd145bb7E74cC2b7329

export const spAVAX_ABI = ${JSON.stringify(abi, null, 2)} as const;
`;

// Write to UI project
const outputPath = path.join(__dirname, '../../sparrow-finance-app/src/contracts/spAVAX-abi.ts');
fs.writeFileSync(outputPath, tsContent);

console.log('✅ ABI exported to:', outputPath);
console.log('📝 Functions exported:', abi.filter(x => x.type === 'function').length);
console.log('📝 Events exported:', abi.filter(x => x.type === 'event').length);
