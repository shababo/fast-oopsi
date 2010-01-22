% this script is a wrapper that loads some data (or simulates it) and then
% calls the most recent FOOPSI function to infer spike trains and
% parameters

clear, clc,
fname = 'spatial_multi';

%% set parameters

% generate spatial filters
Nc      = 2;                                % # of cells in the ROI
neur_w  = 8;                               % height per neuron
height  = 10;                               % height of frame (pixels)
width   = Nc*neur_w;                        % width of frame (pixels)
Npixs   = height*width;                     % # pixels in ROI
x       = linspace(-5,5,width);
y       = linspace(-5,5,height);
[X,Y]   = meshgrid(x,y);
g1      = zeros(Npixs,Nc);
g2      = 0*g1;
Sigma1  = diag([1,1])*3;                    % var of positive gaussian
Sigma2  = diag([1,1])*5;                    % var of negative gaussian
sp      = 1.8;
mu      = [1 1]'*linspace(-sp,sp,Nc);     % means of gaussians for each cell (distributed across pixel space)
w       = ones(1,Nc); %linspace(1,Nc,Nc); %Nc:-1:1;             % weights of each filter
for i=1:Nc
    g1(:,i)  = w(i)*mvnpdf([X(:) Y(:)],mu(:,i)',Sigma1);
    g2(:,i)  = 0*w(i)*mvnpdf([X(:) Y(:)],mu(:,i)',Sigma2);
end

for i=1:Nc
    P.a(:,i)=g1(:,i)-g2(:,i);
end
P.b     = 0.01*mean(P.a); % baseline is a scaled down version of the sum of the spatial filters

% set meta parameters
Meta.T      = 4800;                         % # of time steps
Meta.dt     = 1/60;                           % time step size
Meta.Np     = Npixs;                        % # of pixels in each image
Meta.Nc     = Nc;                           % # cells per ROI
Meta.Poiss  = 0;                            % whether observations are poisson or gaussian
Meta.MaxIter= 25;                           % # iterations of EM to estimate params

% initialize other parameters
P.sig   = 2.7*max(P.a(:));                             % stan dev of noise (indep for each pixel)
C_0     = 0;                                % initial calcium
tau     = rand(Meta.Nc,1)/2+.05;   % decay time constant for each cell
P.gam   = 1-Meta.dt./tau(1:Nc);             % set gam
lam     = linspace(0,4*pi,Meta.T);
P.lam = repmat(exp(1.6*(sin(lam))'),1,Meta.Nc); % rate-ish, ie, lam*dt=# spikes per second
for j=2:Meta.Nc
    P.lam(:,j) = exp(1.6*(sin(lam+pi))');
end
P.lam   = P.lam-repmat(min(P.lam),Meta.T,1);

%% simulate data

n=zeros(Meta.T,Meta.Nc);                         % pre-allocate memory for spike train
C=n;                                        % pre-allocate memory for calcium
for i=1:Meta.Nc
    n(1,i)      = C_0;
    n(2:end,i)  = poissrnd(P.lam(2:end,i)*Meta.dt);  % simulate spike train
    n(n>1)      = 1;                                            % make only 1 spike per bin
    C(:,i)      = filter(1,[1 -P.gam(i)],n(:,i));               % calcium concentration
end
F = P.a*(C+repmat(P.b,Meta.T,1))'+P.sig*rand(Npixs,Meta.T);

figure(2), clf, hold off, plot(P.a(:,1)\F), hold all, plot(P.a(:,2)\F);

save(['../../data/' fname '.mat'],'F','n','P','Meta')

%% generate tif

MakMov  = 0;
if MakMov==1
    FF=uint8(floor(255*z1(F)));
    for t=1:500
        if t==1, mod='overwrite'; else mod='append'; end
        imwrite(reshape(FF(:,t),height,width),['../../data/' fname '.tif'],'tif','Compression','none','WriteMode',mod)
    end
end

%% infer spike trains and parameters

% initialize parameters for estimating parameters (these are only used if MaxIter>1)
Est.sig     = 0;
Est.lam     = 0;
Est.gam     = 0;
Est.b       = 1;
Est.a       = 1;

% initialize parameters for plotting results after each pseudo-EM step
Est.Thresh  = 1;                            % whether to threshold spike train before estimating 'a' and 'b' (we always keep this on)
Est.Plot    = 1;                            % whether to plot filter with each iteration
Est.n       = n;                            % keep true spike times to also plot for comparison purposes
Est.h       = height;                       % height of frame (pixels)
Est.w       = width;                        % width of frame (pixels)


% infer spike trains using a variety of techniques
q=0;
exps=[1 2 2.5];% 3 3.5];
for qq=exps
    disp(qq)
    if qq==1;                                % use true params
        PP=P;
        PP.lam=mean(PP.lam);
        FF=F;
        Meta.MaxIter = 1;
    elseif qq==2                             % use svd spatial filter
        Meta.MaxIter = 1;
        PP=P;
        PP.lam=mean(PP.lam);
        FF=F;
        [U,S,V]=pca_approx(F',Meta.Nc);
        for j=1:Meta.Nc, PP.a(:,j)=V(:,j); end
    elseif qq==2.5
        Meta.MaxIter = 10;
        PP=P;
        PP.lam=mean(PP.lam);
        FF=F;
        [U,S,V]=pca_approx(F',Meta.Nc);
        for j=1:Meta.Nc, PP.a(:,j)=V(:,j); end
    elseif qq==3                           % estimate params
        Meta.MaxIter = 10;
        PP=P;
        FF=F;%-repmat(mean(F,2),1,Meta.T);
        [U,S,V]=pca_approx(FF',Meta.Nc);
        for j=1:Meta.Nc, PP.a(:,j)=V(:,j); end
    elseif qq==3.5                           % estimate params
        Meta.MaxIter = 10;
        PP=P;
        FF=F-repmat(mean(F,2),1,Meta.T);
        [U,S,V]=pca_approx(FF',Meta.Nc);
        for j=1:Meta.Nc, PP.a(:,j)=V(:,j); end
        Est.b=0;
    elseif qq==4                           % estimate params
        Meta.MaxIter = 25;
        PP=P;
        FF=F;
        [U,S,V]=pca_approx(FF',Meta.Nc);
        for j=1:Meta.Nc, PP.a(:,j)=V(:,j); end
        Meta.Plot = 1;
    elseif qq==5                           % estimate params
        Meta.MaxIter = 20;
        Est.Thresh  = 0;
        PP=P;
        [U,S,V]=pca_approx(F',Meta.Nc);
        for j=1:Meta.Nc, PP.a(:,j)=V(:,j); end
    end
    q=q+1;
    [I{q}.n I{q}.P] = FOOPSI_v3_05_01(FF,PP,Meta,Est);
end

save(['../../data/' fname '.mat'],'-append','I','Est')
sound(10*sin(linspace(0,180*pi,2000)))

%% plot results
fname='spatial_multi';
load(['../../data/' fname])
% I{3}=I{2};

Pl.g    = 0.65*ones(1,3);       % gray color
Pl.fs   = 8;                   % font size
Pl.w1   = 0.28;                 % width of subplot
Pl.wh   = [Pl.w1 Pl.w1];        % width and height of subplots
Pl.b1   = 0.67;                 % bottom of topmost subplt
Pl.l1   = 0.41;                 % left side of left subplot on right half
Pl.l2   = Pl.l1+0.3;            % left side of right subplot on right half
Pl.s1   = Pl.w1+0.043;          % space between subplots on right side
Pl.s2   = .33;                  % space between subplots on left side
Pl.ms   = 2;                    % marker size
Pl.lw   = 2;                    % line width
Pl.n    = n; Pl.n(Pl.n==0)=NaN; % true spike train (0's are NaN's so they don't plot)
Pl.T    = Meta.T;
Pl.c    = [0 0 0; Pl.g; 1 1 1]; % colors: black, grey, white
% Pl.c    = get(0,'defaultAxesColorOrder');
Pl.m    = ['v','v'];
Pl.xlim = [400 700]+3000;        % limits of x-axis
Pl.shift= [0 .07];
Pl.x_range = Pl.xlim(1):Pl.xlim(2);
Pl.XTick = [Pl.xlim(1):2/Meta.dt:Pl.xlim(2)];
Pl.XTickLabel = Pl.XTick;
% Pl.XTick= [Pl.xlim(1) round(mean(Pl.xlim)) Pl.xlim(2)];
% Pl.XTickLabel = round((Pl.XTick-min(Pl.XTick))*Meta.dt*100)/100;

% show how our estimation procedure given truth and when estimating spatial filter

figure(1), clf, hold on
% J{1}=I{1}; J{2}=I{3}; I=J;
nrows   = 2; %length(I);
ncols   = 3+Meta.Nc;

Fmean=mean(F);
for q=1:length(exps)
    E{q}.a=I{q}.P.a;
    E{q}.b=I{q}.P.b;
end

% maxx=[]; minn=[];
% for q=1:length(exps)
%     E{q}.a_max=max(E{q}.a(:));
%     E{q}.a_min=min(E{q}.a(:));
%     for j=1:Meta.Nc
%         E{q}.a(:,j)=60*(E{q}.a(:,j)-E{q}.a_min)/(E{q}.a_max-E{q}.a_min);
%     end
% end

% make images on same scale
immax=max((P.a(:)));
immin=min((P.a(:)));
for q=1:2
    immax=max(immax,max(E{q}.a(:)));
    immin=min(immin,min(E{q}.a(:)));
end

PP.a=60*(P.a-immin)/(immax-immin);

for q=1:2
    for j=1:2
        EE{q}.a(:,j)=60*(E{q}.a(:,j)-immin)/(immax-immin);
    end
end



for q=1:2
    % align inferred cell with actual one
    j_inf=0*n(1:Meta.Nc);
    cc=0*n(1:Meta.Nc,:);
    for j=1:Meta.Nc
        for k=1:Meta.Nc
            cc_temp = corrcoef(n(:,j),I{q}.n(:,k));
            cc(k,j)   = cc_temp(2);
        end
    end
    [foo ind] = max(cc);
    sortI = sort(ind);
    if ~any(diff(sortI)==0)
        j_inf=ind;
    else
        [foo ind]=max(cc(:));
        j_inf(1)=(ind+1)/2;
        if j_inf(1)==1; j_inf(2)=2;
        else j_inf(1)=2; j_inf(2)=1; end
    end
end



% plot mean image frame
subplot(nrows,ncols,1)
image(reshape(sum(PP.a,2),Est.h,Est.w))
set(gca,'XTick',[],'YTick',[])
colormap gray
ylabel([{'Crude'}; {'Multicellular ROI'}],'FontSize',Pl.fs);

% plot F
q=1;
subplot(nrows,ncols,ncols+1), hold on
for j=1:Meta.Nc
    F_proj=E{q}.a(:,j_inf(j))\F;
    plot(0.9*z1(F_proj(Pl.x_range)),'Color',Pl.c(j,:),'LineWidth',1)
    stem(Pl.n(Pl.x_range,j)-Pl.shift(j),'LineStyle','none','Marker',Pl.m(j),'MarkerEdgeColor',Pl.c(j,:),'MarkerFaceColor',Pl.c(j,:),'MarkerSize',Pl.ms)
    axis([Pl.xlim-Pl.xlim(1) 0 1])
    set(gca,'YTick',[0 1],'YTickLabel',[])
    if q==1
        ylab=ylabel([{'Fluorescence'}; {'Projection'}],'FontSize',Pl.fs);
        set(gca,'XTick',Pl.XTick-min(Pl.XTick),'XTickLabel',(Pl.XTick-min(Pl.XTick))*Meta.dt,'FontSize',Pl.fs)
        xlabel('Time (sec)','FontSize',Pl.fs)
    else
        set(gca,'XTick',Pl.XTick-min(Pl.XTick),'XTickLabel',[])
    end
end


I{2}=I{3};

for q=1:2%length(exps)

    % plot spatial filters
    for j=1:Meta.Nc,
        subplot(nrows,ncols,1+q+(j-1)*2)
        image(reshape(EE{q}.a(:,j_inf(j)),Est.h,Est.w)),
        set(gca,'XTickLabel',[],'YTickLabel',[])

        if q==1,
            %             ylabel(['Neuron ' num2str(j)],'FontSize',Pl.fs);
            ylabel([{'Spatial'}; {'Filter'}],'FontSize',Pl.fs);
            title('Truth','FontSize',Pl.fs),
        else
            title('Estimated','FontSize',Pl.fs)
        end
    end


    % plot inferred spike train
    for j=1:Meta.Nc
        %         subplot(nrows,ncols,3+q+(j-1)*ncols)
        subplot(nrows,ncols,1+q+(j-1)*2+ncols)
        hold on
        stem(Pl.x_range,Pl.n(Pl.x_range,j)+.03,'LineStyle','none','Marker','v','MarkerEdgeColor',Pl.c(j,:),'MarkerFaceColor',Pl.c(j,:),'MarkerSize',Pl.ms)
        if j==1, k=2; else k=1; end
        if q==1, kk=j; end %else if j==1, kk=2; else kk=1; end, end%j_inf(j);
        kk=j;
        bar(Pl.x_range,I{q}.n(Pl.x_range,kk)/max(I{q}.n(Pl.x_range,j_inf(j))),'EdgeColor',Pl.c(j,:),'FaceColor',Pl.c(j,:))
        axis('tight')
        set(gca,'YTick',[0 1],'YTickLabel',[])
        set(gca,'XTick',Pl.XTick,'XTickLabel',(Pl.XTick-min(Pl.XTick))*Meta.dt,'FontSize',Pl.fs)
        xlabel('Time (sec)','FontSize',Pl.fs)
        if q==1
            ylabel([{'Spike'}; {'Inference'}],'FontSize',Pl.fs)
            %             xlabel('Time (sec)','FontSize',Pl.fs)
        else
        end
    end

end

% neuron={'                 Neuron 1'};
% annotation(gcf,'textbox',[0.2642 0 0.3248 0.6531],'String',neuron,'FitBoxToText','off');

% print fig
wh=[7 2];   %width and height
DirName = '../../figs/';
PrintFig(wh,DirName,fname);
