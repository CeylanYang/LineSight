import base64
import io
import cv2
import numpy as np
from django.test import TestCase
from django.contrib.auth import get_user_model
from rest_framework.test import APIClient
from . import tests as workflow_tests
from .models import Evidence
from .vision import ALGORITHM, skeletonize, edge_image, camera_image

class VisionTests(TestCase):
    setUp = workflow_tests.WorkflowApiTests.setUp
    to_inspection = workflow_tests.WorkflowApiTests.to_inspection
    def test_old_preview_regenerates_once_after_authorization(self):
        from django.core.files.uploadedfile import SimpleUploadedFile
        job=self.client.post(f'/api/v1/workspaces/{self.ws}/jobs/',{'part_name':'Contour','printer':'A1','quantity':1},format='json').data
        self.to_inspection(job['id'])
        decoded=camera_image(self.frame())
        _,png=cv2.imencode('.png',decoded)
        base=f"/api/v1/workspaces/{self.ws}/jobs/{job['id']}/evidence/"
        upload=self.client.post(base,{'image':SimpleUploadedFile('photo.png',png.tobytes(),content_type='image/png')},format='multipart')
        self.assertEqual(upload.status_code,201,upload.data)
        row=Evidence.objects.get(pk=upload.data['id']); original=row.image.name
        Evidence.objects.filter(pk=row.pk).update(preview_algorithm='legacy')
        path=base+f'{row.pk}/preview/'
        foreign=APIClient(); foreign.force_authenticate(get_user_model().objects.create_user(username='preview-other'))
        self.assertEqual(foreign.get(path).status_code,404)
        row.refresh_from_db(); self.assertEqual(row.preview_algorithm,'legacy')
        response=self.client.get(path)
        self.assertEqual(b''.join(response.streaming_content),edge_image(decoded)[0])
        row.refresh_from_db(); self.assertEqual(row.preview_algorithm,ALGORITHM)
        self.assertEqual(row.image.name,original)
        filename=row.edge_preview.name
        response=self.client.get(path); b''.join(response.streaming_content)
        row.refresh_from_db(); self.assertEqual(row.edge_preview.name,filename)
    def frame(self):
        y=np.full((48,64),180,dtype=np.uint8); y[12:36,16:48]=30
        return {'width':64,'height':48,'format':'yuv420','planes':[
            {'bytes':base64.b64encode(p.tobytes()).decode(),'row_stride':p.shape[1],'pixel_stride':1}
            for p in [y,np.full((24,32),128,dtype=np.uint8),np.full((24,32),128,dtype=np.uint8)]]}
    def test_skeleton_retains_components_is_thin_and_idempotent(self):
        thick=np.zeros((60,80),dtype=np.uint8); thick[5:40,10:35]=255; thick[12:50,50:70]=255
        thin=skeletonize(thick)
        self.assertLess(np.count_nonzero(thin),np.count_nonzero(thick)//4)
        self.assertEqual(cv2.connectedComponents(thin)[0],3)
        np.testing.assert_array_equal(skeletonize(thin),thin)
        png,edges=edge_image(np.dstack([thick]*3))
        self.assertTrue(png.startswith(b'\x89PNG')); self.assertGreater(np.count_nonzero(edges),0)
    def test_frame_stride_rotation_and_buffer_validation(self):
        data=self.frame(); data['rotation']=90
        self.assertEqual(camera_image(data).shape,(64,48,3))
        data['planes'][0]['bytes']='broken'
        with self.assertRaises(ValueError): camera_image(data)
    def test_frame_endpoint_and_lookup_are_workspace_authorized(self):
        from django.core.cache import cache
        cache.clear()
        path=f'/api/v1/workspaces/{self.ws}/vision/frame/'
        response=self.client.post(path,self.frame(),format='json')
        self.assertEqual(response.status_code,200,response.data)
        self.assertEqual(response.data['algorithm'],ALGORITHM)
        self.assertTrue(base64.b64decode(response.data['edge_png']).startswith(b'\x89PNG'))
        self.assertEqual(Evidence.objects.count(),0)
        self.assertEqual(self.client.post(path,{**self.frame(),'width':4096},format='json').status_code,400)
        foreign=APIClient(); foreign.force_authenticate(get_user_model().objects.create_user(username='vision-other'))
        self.assertEqual(foreign.post(path,self.frame(),format='json').status_code,404)
        lookup=f'/api/v1/workspaces/{self.ws}/trace/lookup/'
        job=self.client.post(f'/api/v1/workspaces/{self.ws}/jobs/',{'part_name':'Trace','printer':'A1','quantity':1,'batch_code':'B-7','tracking_mode':'serial','serial_numbers':['SN-7']},format='json').data
        for code in ['B-7','SN-7']:
            self.assertEqual([row['id'] for row in self.client.get(lookup,{'code':code}).data['jobs']],[job['id']])
        self.assertEqual(self.client.get(lookup,{'code':'missing'}).data['jobs'],[])
        self.assertEqual(foreign.get(lookup,{'code':'B-7'}).status_code,404)
        self.assertEqual(APIClient().post(path,self.frame(),format='json').status_code,401)
