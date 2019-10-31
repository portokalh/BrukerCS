close all
clear;clc

% !!! Download 'bruker_img.mat' from the BassData folder on Box so you
% don't have to run RussRecon

% This script loads in k space data and displays a slice of the image data.
% It then uses a sampling mask to generate undersampled k space data and
% displays three different types of reconstructions: zero-filled recon
% (i.e. directly reconstructing the data), SENSE reconstruction
% (autocalibrated), and ESPIRiT reconstruction (using ESPIRiT calibration)

% BART must be installed for bart commands to work
% %! means these settings must be changed for each user depending on where
% your code/BART path is
% %* means you can toggle these options

main_dir = '/Users/janetchen/Documents/Bass Connections'; %!
bartpath = '/Applications/bart/matlab'; %!*
setenv('TOOLBOX_PATH','/Applications/bart') %!

% The following packages are needed in your main directory:
paths = {main_dir;[main_dir '/STI_Suite_v2/STI_Suite_v2.1/Source Code_v2.1'];...
    [main_dir '/RussRecon'];[main_dir '/ImageProcessing'];...
    [main_dir '/NIfTI_20140122'];[main_dir '/MultipleEchoRecon'];...
    [main_dir '/XCalc']};

% If you need to extract the image data, you need to have the .work folder
% in the main directory. If you're loading it in (and bruker_img.MAT should
% be in the addecode main directory), you don't need this folder
workpath = [main_dir '/B04027.work'];

use_espirit_img = false; %* try out the example image or use our image?
% If you want to use the example image, the BART folder at
% https://github.com/mikgroup/espirit-matlab-examples must be downloaded
% (or just the 'full.cfl' from the 'data' folder)
bart_mask = false; %* use variable density Poisson mask generated by BART
% code (true), or code from BJ Anderson (false)?

load_img = true; %* 'true' if you have the image saved and don't want to
% run get_RussRecon_img again
save_img = false;
img_path = 'bruker_img.mat'; % image path if it's already been saved

if ~use_espirit_img && ~load_img % Need to be in workpath for RussRecon
    addpath(pwd)
    cd(workpath)
end
addpath(bartpath)
for ii = 1:length(paths)
    addpath(paths{ii,1})
end

if use_espirit_img
    img = readcfl(sprintf('%s/BART/espirit-matlab-examples-master/data/full',main_dir));
else
    if load_img
        load(sprintf('%s/%s',main_dir,img_path))
    else
        img=get_RussRecon_img('bruker','center','save');
        if save_img
            save(sprintf('%s/%s',main_dir,img_path),'bruker_img')
        end
    end
end

%cflpath = sprintf('%s/img',paths{2,1});
%writecfl(cflpath,img)

% The MRI-specific BART commands assume that the first three dimensions
% represent space/spatial k-space, the next two dimensions represent coils
% and ESPIRiT maps, and the 10th dimension (zero-indexing) represents
% temporal phases.

num_coils = size(img,4);
if use_espirit_img
    % img is 1x230x180x8
    % Swap x, y, z dimensions so 3rd dimension is 1
    img_echo1 = permute(img(1,:,:,1:num_coils),[2,3,1,4]); 
    % Take inverse Fourier transform
    coilimg = bart('fft -i 6', img);
    % coilimg = ifftnc(img);
    % Get root sum of squares
    plot_img = bart('rss 4',squeeze(coilimg));
    orig_slice = 1;
    slice = orig_slice;
    coil = 1;
    sz_x = size(img,2); sz_y = size(img,3);
else
    % Z-axis slice
    slice = 52;
    orig_slice = slice;
    % 8 echoes, 2 coils
    % Original image is 192x192x90x8x2, or x, y, z, # echoes, # coils
    sz_x = size(img,1); sz_y = size(img,2);
    % To match espirit 'full' img dimensions (XxYxcoils, 230x180x8), slice
    % in z-dimension
    % img_echo1 here is 192x192x2 (XxYxcoils)
    temp = bart('fft -i 7',squeeze(img(:,:,:,1,:)));
    temp_slice = temp(:,:,slice,:);
    img_echo1 = bart('fft 7',temp_slice);
    
    coilimg = bart('fft -i 7',img_echo1);
    % Other method to get ifft
    % coilimg = ifftnc(img_echo1);
    
    rss = bart('rss 4', squeeze(coilimg));
    plot_img = rss;
    
    slice = 1;
    
    % Coil #
    coil = 1;
end

fig = figure;
ax = gca;

imshow(abs(plot_img),[])
title(ax,'Original image','FontSize',15)
set(fig,'Position',[50 600 300 250])

%% Generate sampling pattern and undersample K-space

if bart_mask
    % bart poisson -Y $dim -Z $dim -y $yaccel -z $zaccel -C $caldim -v -e mask
    % -Y: dim 1. -Z: dim 2. -v: variable density (which the workshop uses)
    % -e: elliptical scanning
    % Default values: Y: 192, Z: 192, y: 1.5, z: 1.5, C: 32
    % Change C to 20?
    % ~25% of elements in und2x2 were nonzero, while ~13.5% are nonzero here
    num_points = sz_x*sz_y*0.25;
    sampling_pattern = bart(sprintf('poisson -Y %d -Z %d -y 1 -z 1 -C 32 -R %d -v -e',sz_x,sz_y,num_points));% -v -e');
else
    % Mask from BJ Anderson's code
    acceleration=2; %* Undersample by a factor of <acceleration>
    pa=2.3;
    pb=5.6;
    
    sampling_pattern = sampling_mask(acceleration,sz_x,sz_y,pa,pb);
end

sampling_pattern = squeeze(sampling_pattern);

fprintf(sprintf('Mask non-zero percentage: %.2f%%',length(find(sampling_pattern ~= 0))/numel(sampling_pattern)*100))
fprintf('\n')

fig2 = figure;
s1 = subplot(1,3,1);
imagesc(abs(squeeze(img_echo1(:,:,slice,coil))))
title(sprintf('Original K-space for coil %d',coil),'FontSize',15)

s2 = subplot(1,3,2);
imagesc(sampling_pattern);
title('Sampling pattern','FontSize',15)

% Zero out unsampled areas through element-by-element multiplication with
% sampling pattern
% 'us' means 'undersampled'
us_img_echo1 = bart('fmac',squeeze(img_echo1),sampling_pattern); % img_echo1.*sampling_pattern;

s3 = subplot(1,3,3);
imagesc(abs(us_img_echo1(:,:,slice,coil)))
title(sprintf('Undersampled K-space for coil %d',coil),'FontSize',15)

s = suptitle(sprintf('Slice %d of z-axis',orig_slice));
set(s,'FontSize',16,'FontWeight','bold')
set(fig2,'Position',[300 600 800 300])

if use_espirit_img
    n = num_coils;
else
    n = 2; % 2 x n espirit maps, we have 2 coils
end

%% Zero-filled reconstruction versus ESPIRiT
% Zero-filled reconstruction

us_coilimg = bart('fft -i 7',us_img_echo1);
us_rss = bart('rss 8', us_coilimg);

% Add singleton dimension so first 3 dimensions reflect x, y, z
us_img_echo1_slice = permute(us_img_echo1,[1,2,4,3]);

% !!! assess quality of reconstruction with difference map

% SENSE reconstruction
sensemaps = bart('caldir 20', us_img_echo1_slice);
sensereco = bart('pics -r0.01', us_img_echo1_slice, sensemaps);

% ESPIRiT reconstruction

% Dimensions from espirit.m
% Input to this was 1x230x180x8 (breaks if input is 3D). Expects 3 k space
% dimensions, 1 coil dimension
% calib dims: 1x230x180x8x2 (two sets of maps)
% emaps dims: 1x230x180x1x2
% [calib emaps] = bart('ecalib -r 20', <image slice>);
% r: cal size. m: # maps
espiritmaps = bart('ecalib -r 20 -k 5 -m 2', us_img_echo1_slice); %bart('ecalib -S', us_img_slice_dim4);

% Plots

% View ESPIRiT maps
fig3 = figure;
ax = gca;
imshow3(abs(squeeze(espiritmaps)),[],[2,n])
title(ax,'ESPIRiT maps','FontSize',15)
set(fig3,'Position',[50 100 400 400])

% View ESPIRiT reconstruction
fig4 = figure;
subplot(2,2,1)
ax = gca;
imshow(abs(us_rss(:,:,slice)),[])
title(ax,'Zero-filled reconstruction','FontSize',15);

% Note: zero-indexing

% Comment out if combining 2 sets of maps
% espiritmaps = espiritmaps(:,:,:,:,1); % MATLAB equivalent

% size of input 1 = size of input 2
% l1-wavelet, l2 regularization
% r: regularization parameter
reco = bart('pics -l2 -r0.01', us_img_echo1_slice, espiritmaps);
% espiritreco_rss dims in espirit.m were 1x320x252
reco_rss = bart('rss 16', reco);

subplot(2,2,2)
ax = gca;
imshow(abs(squeeze(reco(:,:,:,1,1))), [])
title(ax,'ESPIRiT recon (map 1)','FontSize',15)

% This image should be the closest to fully sampled
subplot(2,2,3)
ax = gca;
imshow(squeeze(reco_rss),[]);
title(ax,'ESPIRiT rss','FontSize',15)

subplot(2,2,4)
ax = gca;
imshow(abs(squeeze(sensereco)),[])
title(ax,'SENSE reconstruction','FontSize',15)
set(fig4,'Position',[450 100 400 400])