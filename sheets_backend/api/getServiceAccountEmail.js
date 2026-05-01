const fs = require('fs');
const path = require('path');

module.exports = async (req, res) => {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') {
    return res.status(204).end();
  }

  try {
    let keyFile;
    if (process.env.SERVICE_ACCOUNT_JSON) {
      keyFile = JSON.parse(process.env.SERVICE_ACCOUNT_JSON);
    } else {
      const keyPath = path.join(__dirname, '..', 'service_account.json');
      keyFile = JSON.parse(fs.readFileSync(keyPath, 'utf8'));
    }
    
    return res.json({ serviceAccountEmail: keyFile.client_email });
  } catch (error) {
    console.error('Email Proxy Error:', error);
    return res.status(500).json({ error: 'Failed to read service account email' });
  }
};
