const https = require('https');
const buckets = ['stitch-assets', 'stitch-artifacts', 'stitch-exports', 'aida-stitch-assets', 'makani-stitch-assets', 'stitch-prod', 'gemini-stitch-assets', 'cider-stitch-assets'];
const id = '06f20ab7899840f582a759b114e2847e';
const projectId = '16439287358814480746';

buckets.forEach(b => {
    // try bare id
    https.request({ method: 'HEAD', host: 'storage.googleapis.com', path: `/${b}/${id}.png` }, res => {
        if(res.statusCode === 200) console.log(`FOUND: /${b}/${id}.png`);
    }).end();
    
    // try with project id
    https.request({ method: 'HEAD', host: 'storage.googleapis.com', path: `/${b}/${projectId}/${id}.png` }, res => {
        if(res.statusCode === 200) console.log(`FOUND: /${b}/${projectId}/${id}.png`);
    }).end();

    // try projects/project/screens/screen
    https.request({ method: 'HEAD', host: 'storage.googleapis.com', path: `/${b}/projects/${projectId}/screens/${id}.png` }, res => {
        if(res.statusCode === 200) console.log(`FOUND: /${b}/projects/${projectId}/screens/${id}.png`);
    }).end();
});
