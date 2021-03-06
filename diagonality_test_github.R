
######################################################################
# R code for diagonality test via mxPBF.
#
# References
# - Kyoungjae Lee, Lizhen Lin and David Dunson. (2018) Maximum Pairwise Bayes Factors for Covariance Structure Testing. [https://arxiv.org/abs/1809.03105]
# - Wei Lan, Ronghua Luo, Chih-Ling Tsai, Hansheng Wang and Yunhong Yang. (2015) Testing the Diagonality of a Large Covariance Matrix in a Regression Setting.
# - Tony Cai and Tiefeng Jiang. (2011) LIMITING LAWS OF COHERENCE OF RANDOM MATRICES WITH APPLICATIONS TO TESTING COVARIANCE STRUCTURE AND CONSTRUCTION OF COMPRESSED SENSING MATRICES
#
# made by Kyoungjae Lee.
# version 1 (Sep. 09, 2018)
######################################################################

##################################################################
# Functions
##################################################################
# mxPBF for diagonality test
mxPBF.diag <- function(X, a0, b0, gamma){
   ###############################################################
   # Input 
   #     X: n times p data matrix
   #     a0, b0, gamma: hyperparameters for mxPBF
   #
   # Output
   #     log.BF.mat: p times p matrix of pairwise log Bayes factors
   #                 The (i,j)th entry of log.BF.mat is the pairwise log Bayes factor, 
   #                 log BF_{10}(X_i, X_j).
   #
   # Description:
   #     Let X_i be the i-th column of X.
   #     [Model]
   #        X_i | X_j ~ N_n( a_{ij}X_j, \tau_{ij}^2 I_n )
   #     [Hypothesis testing]
   #        H_0: a_{ij}=0  versus  H_1: not H_0
   #     [Prior]
   #        under H_0: \tau_{ij}^2 ~ IG(a0, b0)
   #        under H_1: a_{ij}|\tau_{ij}^2 ~ N(0, \tau_{ij}^2/[gamma*||X_j||^2])
   #                   \tau_{ij}^2 ~ IG(a0, b0)
   ###############################################################
   p = ncol(X)
   n = nrow(X)
   log.BF.mat = matrix(0, ncol=p,nrow=p) # log Bayes factors
   
   for(i in 1:p){
      Xi = matrix(X[,i], ncol=1)
      for(j in (1:p)[-i]){
         Xj = matrix(X[,j], ncol=1)
         log.BF.mat[i,j] = 1/2 * log(gamma/(1+gamma)) -
            (n/2 + a0) * ( log(( sum((Xi)^2) - sum(Xi*Xj)^2/sum((Xj)^2) /(1+gamma) ) + 2*b0) - log( sum((Xi)^2) + 2*b0) )
      }
   }
   diag(log.BF.mat) = log.BF.mat[1,2] # just to fill out the diagonal parts
   return(log.BF.mat)
}

# Lan et al. (2015)'s test for diagonality
Lan.test <- function(X, alpha=0.05){
   p = ncol(X)
   n = nrow(X)
   z.val = qnorm(1 - alpha)
   
   Sg.hat = 0
   for(i in 1:n){
      X.i = matrix(X[i,], ncol=1)
      Sg.hat = Sg.hat + X.i%*%t(X.i)/n
   }
   Sg.hat2 = Sg.hat^2
   
   Bias.hat = sqrt(n)/(2*p^{3/2}) * ( sum(diag(Sg.hat))^2 - sum(diag(Sg.hat2)) )
   M2p.hat = n/(p*(n+2)) * sum(diag(Sg.hat2))
   Tstat = 0
   for(j1 in 1:(p-1)){
      for(j2 in (j1+1):p){
         Tstat = Tstat + (n/p)^{3/2} * Sg.hat2[j1, j2]
      }
   }
   Tn = (Tstat - Bias.hat) / (sqrt(n/p)*M2p.hat)
   
   res = list()
   res$Tn = Tn
   res$test = ( Tn > z.val )
   return( res )
}

# Cai and Jiang (2011)'s test
CJ.test <- function(X, alpha=0.05){
   p = ncol(X)
   n = nrow(X)
   
   Rho = matrix(0, p,p)
   for(i in 1:p){
      X.i = matrix(X[,i], ncol=1)
      for(j in (1:p)[-i]){
         X.j = matrix(X[,j], ncol=1)
         Rho[i,j] = sum(X.i*X.j) / sqrt( sum( X.i^2 )*sum( X.j^2 ) )
      }
   }
   Ln = max(abs(Rho))
   Tn = n*(Ln)^2 - 4*log(p) + log(log(p))
   
   res = list()
   res$Tn = Tn
   res$test = ( Tn > -log(8*pi) - 2*log(log(1/(1-alpha))) )
   return( res )
}

# auxiliary function for tridiagonal matrix
tridiag <- function(upper.val, lower.val, diag.val){ 
   p = length(diag.val)
   res = matrix(0, p, p)
   ind = 1:(p-1)
   res[ cbind(ind+1, ind) ] = lower.val
   res[ cbind(ind, ind+1) ] = upper.val
   diag(res) = diag.val
   return(res)
}

library(MCMCpack)
library(MASS)
library(doMC)

##################################################################
# Simulations
##################################################################
n.sim = 100 # number of simulations
p = 200 # number of variables
n = 100 # number of observations
registerDoMC(1) # number of cores to use
# registerDoMC(20)

##########################################
# Under H0
##########################################
tot.res0 <- foreach (sim = 1:n.sim) %dopar% {
   tot.res.mat = matrix(0, nrow = 1, ncol = 3)
   set.seed(sim)
   Sigma0 = diag(p) 
   X = mvrnorm(n = n, mu = rep(0, p), Sigma = Sigma0) # data generation
   
   # hyperparameters for mxPBF
   a0 = 2; b0 = 2; c_gam = 10; alpha = 4.01*(1-1/log(n))
   gamma = c_gam*max(n,p)^{-alpha}
   
   log.BF.mat = mxPBF.diag(X, a0, b0, gamma)
   tot.res.mat[, 1] = max(log.BF.mat) # mxPBF
   tot.res.mat[, 2] = Lan.test(X)$Tn # Lan et al's test
   tot.res.mat[, 3] = CJ.test(X)$Tn # Cai and Jiang's test
   return(tot.res.mat)
}# data.ind for loop


##########################################
# Under H1
##########################################
# magnitude of signals in H1
rho.vec = seq(from = 0.3, to = 0.8, by = 0.025) # (1) tridiagonal
# rho.vec = seq(from = 0.1, to = 0.5, by = 0.025) # (2) sparse signals
rho.length = length(rho.vec)

tot.res1 <- foreach (sim = 1:n.sim) %dopar% {
   test.mat = matrix(0, nrow = rho.length, ncol = 3)
   for(rho.ind in 1:rho.length){
      set.seed(sim)
      
      # under H1
      rho = rho.vec[rho.ind]
      Sigma0 = diag(p)
      
      Sigma0 = tridiag(rep(rho, p-1), rep(rho, p-1), rep(1, p)) # (1) tridiagonal
      # Sigma0[1,2] = rho; Sigma0[2,1] = rho # (2) Sparse signals
      
      X = mvrnorm(n = n, mu = rep(0, p), Sigma = Sigma0) # data generation
      
      # hyperparameters for mxPBF
      a0 = 2; b0 = 2; c_gam = 10; alpha = 8.01*(1-1/log(n))
      gamma = c_gam*max(n,p)^{-alpha}
      
      log.BF.mat = mxPBF.diag(X, a0, b0, gamma)  
      test.mat[rho.ind, 1] = max(log.BF.mat) # mxPBF
      test.mat[rho.ind, 2] = Lan.test(X)$Tn # Lan et al's test
      test.mat[rho.ind, 3] = CJ.test(X)$Tn # Cai and Jiang's test
   } # rho.ind for loop   
   return(test.mat)
}# data.ind for loop


##################################################################
# Results
##################################################################
rho.ind = 5 # Check the results for rho.vec[rho.ind], where rho.vec[rho.ind] is the magnitude of signals in H1

thr.BF = c(-(30:11), -seq(10, 0.01, by=-0.01), -0.005, -0.001, -0.0005, 0, 0.2, 0.4, 0.6, 0.8, 1, 2, 6, 8, 10, 15, 100) # thresholds for mxPBF
thr.Fq = c(seq(0.99, 0.06, by=-0.01), seq(0.05, 0.00001, by=-0.00001), 0.000001, 0.0000001, 0.00000001, 0.1^{20}) # significant levels for frequentist tests

TPR.mxPBF = rep(0, length(thr.BF)); FPR.mxPBF = rep(0, length(thr.BF))
TPR.TC = rep(0, length(thr.BF)); FPR.TC = rep(0, length(thr.BF))
TPR.MS = rep(0, length(thr.BF)); FPR.MS = rep(0, length(thr.BF))

# TPR and FPR for mxPBF
for(thr.ind in 1:length(thr.BF)){
   res0 = rep(0, 3); res1 = rep(0, 3)
   for(ii in 1:n.sim){
      res0[1] = res0[1] + (tot.res0[[ii]][, 1] > thr.BF[thr.ind])
      res1[1] = res1[1] + (tot.res1[[ii]][rho.ind, 1] > thr.BF[thr.ind])
   }
   table.mxPBF = matrix(0, 2,2, dimnames = list(c("H0", "H1"), c("H0.pred", "H1.pred")))
   
   table.mxPBF[1,1] = n.sim - res0[1]; table.mxPBF[1,2] = res0[1]
   table.mxPBF[2,1] = n.sim - res1[1]; table.mxPBF[2,2] = res1[1]
   
   TPR.mxPBF[thr.ind] = table.mxPBF[2,2]/n.sim
   FPR.mxPBF[thr.ind] = table.mxPBF[1,2]/n.sim
}

# TPR and FPR for frequentist tests
for(thr.ind in 1:length(thr.Fq)){
   z.val = qnorm(1 - thr.Fq[thr.ind])
   res0 = rep(0, 3); res1 = rep(0, 3)
   for(ii in 1:n.sim){
      res0[2] = res0[2] + (tot.res0[[ii]][, 2] > z.val*2*sqrt(p*(p+1) /(n*(n-1))))
      res1[2] = res1[2] + (tot.res1[[ii]][rho.ind, 2] > z.val*2*sqrt(p*(p+1) /(n*(n-1))))
      res0[3] = res0[3] + (tot.res0[[ii]][, 3] > z.val)
      res1[3] = res1[3] + (tot.res1[[ii]][rho.ind, 3] > z.val)
   }
   table.TC = matrix(0, 2,2, dimnames = list(c("H0", "H1"), c("H0.pred", "H1.pred")))
   table.MS = matrix(0, 2,2, dimnames = list(c("H0", "H1"), c("H0.pred", "H1.pred")))
   
   table.TC[1,1] = n.sim - res0[2]; table.TC[1,2] = res0[2]
   table.TC[2,1] = n.sim - res1[2]; table.TC[2,2] = res1[2]
   table.MS[1,1] = n.sim - res0[3]; table.MS[1,2] = res0[3]
   table.MS[2,1] = n.sim - res1[3]; table.MS[2,2] = res1[3]
   
   TPR.TC[thr.ind] = table.TC[2,2]/n.sim
   FPR.TC[thr.ind] = table.TC[1,2]/n.sim
   TPR.MS[thr.ind] = table.MS[2,2]/n.sim
   FPR.MS[thr.ind] = table.MS[1,2]/n.sim
}


# ROC curve
tit = paste(c("(n,p)=","(",n,",",p,")", " / ", "rho=" ,rho.vec[rho.ind]), collapse = "")
par(mar = c(5,5,4,2) + 0.1)
plot(x = FPR.mxPBF, y = TPR.mxPBF, type="l", lwd=2, xlim=c(0,1), ylim=c(0,1), xlab="FPR", ylab="TPR", main = tit, cex.main=2.5, cex.lab=2, cex.axis=2)
lines(x = FPR.TC, y = TPR.TC, type="l", lwd=2, col=2)
lines(x = FPR.MS, y = TPR.MS, type="l", lwd=2, col=4)
legend("bottomright", c("mxPBF", "CM", "SYK"), lty = c(1,1,1), col=c(1,2,4), lwd=c(2,2,2), pt.cex=1, cex=2)




